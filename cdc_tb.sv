`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.10.2026 22:46:06
// Design Name: 
// Module Name: cdc_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

interface cdc_if (input logic wclk, input logic rclk);

    logic        reset;
    logic [31:0] data_in_w;
    logic        data_in_valid;
    logic        data_in_ready;
    logic [31:0] data_out_r;
    logic        data_out_valid;
    logic        data_out_ready;

    clocking wdrv_cb @(posedge wclk);
        default input #1step output #1;
        output data_in_w, data_in_valid;
    endclocking

    clocking rdrv_cb @(posedge rclk);
        default input #1step output #1;
        output data_out_ready;
    endclocking

    clocking wmon_cb @(posedge wclk);
        default input #1step;
        input data_in_w, data_in_valid, data_in_ready;
    endclocking

    clocking rmon_cb @(posedge rclk);
        default input #1step;
        input data_out_r, data_out_valid, data_out_ready;
    endclocking

endinterface


class transaction;
    rand bit [31:0]   data;
    rand int unsigned gap;
    constraint c_gap { gap inside {[0:3]}; }
endclass


class generator;
    mailbox #(transaction) gen2drv;
    int unsigned           gap_max;
    int unsigned           sent;

    function new(mailbox #(transaction) gen2drv);
        this.gen2drv = gen2drv;
        this.gap_max = 3;
        this.sent    = 0;
    endfunction

    task run(input int unsigned num);
        transaction tr;
        repeat (num) begin
            tr = new();
            if (!tr.randomize() with { gap <= local::gap_max; })
                $fatal(1, "randomize failed");
            gen2drv.put(tr);
            sent++;
        end
    endtask
endclass


class monitor;
    virtual cdc_if         vif;
    mailbox #(transaction) mon2scb_wr;
    mailbox #(transaction) mon2scb_rd;
    int unsigned           wr_count;
    int unsigned           rd_count;
    event                  wr_acc;

    function new(virtual cdc_if vif,
                 mailbox #(transaction) mon2scb_wr,
                 mailbox #(transaction) mon2scb_rd);
        this.vif        = vif;
        this.mon2scb_wr = mon2scb_wr;
        this.mon2scb_rd = mon2scb_rd;
        this.wr_count   = 0;
        this.rd_count   = 0;
    endfunction

    task monitor_write();
        transaction tr;
        forever begin
            @(vif.wmon_cb);
            if (vif.reset && vif.wmon_cb.data_in_valid && vif.wmon_cb.data_in_ready) begin
                tr = new();
                tr.data = vif.wmon_cb.data_in_w;
                mon2scb_wr.put(tr);
                wr_count++;
                -> wr_acc;
            end
        end
    endtask

    task monitor_read();
        transaction tr;
        forever begin
            @(vif.rmon_cb);
            if (vif.reset && vif.rmon_cb.data_out_valid && vif.rmon_cb.data_out_ready) begin
                tr = new();
                tr.data = vif.rmon_cb.data_out_r;
                mon2scb_rd.put(tr);
                rd_count++;
            end
        end
    endtask

    task run();
        fork
            monitor_write();
            monitor_read();
        join
    endtask
endclass


class driver;
    virtual cdc_if         vif;
    mailbox #(transaction) gen2drv;
    monitor                mon;
    bit                    busy;
    bit                    r_enable;
    int unsigned           r_ready_pct;

    function new(virtual cdc_if vif, mailbox #(transaction) gen2drv, monitor mon);
        this.vif         = vif;
        this.gen2drv     = gen2drv;
        this.mon         = mon;
        this.busy        = 1'b0;
        this.r_enable    = 1'b1;
        this.r_ready_pct = 100;
    endfunction

    task drive_write();
        transaction tr;
        vif.wdrv_cb.data_in_valid <= 1'b0;
        vif.wdrv_cb.data_in_w     <= '0;
        forever begin
            gen2drv.get(tr);
            busy = 1'b1;
            if (tr.gap != 0) begin
                vif.wdrv_cb.data_in_valid <= 1'b0;
                repeat (tr.gap) @(vif.wdrv_cb);
            end
            vif.wdrv_cb.data_in_w     <= tr.data;
            vif.wdrv_cb.data_in_valid <= 1'b1;
            @(mon.wr_acc);
            vif.wdrv_cb.data_in_valid <= 1'b0;
            busy = 1'b0;
        end
    endtask

    task drive_read();
        vif.rdrv_cb.data_out_ready <= 1'b0;
        forever begin
            @(vif.rdrv_cb);
            vif.rdrv_cb.data_out_ready <= r_enable && ($urandom_range(99) < r_ready_pct);
        end
    endtask

    task run();
        fork
            drive_write();
            drive_read();
        join
    endtask
endclass


class scoreboard;
    mailbox #(transaction) mon2scb_wr;
    mailbox #(transaction) mon2scb_rd;
    int unsigned           cmp_count;
    int unsigned           err_count;

    function new(mailbox #(transaction) mon2scb_wr,
                 mailbox #(transaction) mon2scb_rd);
        this.mon2scb_wr = mon2scb_wr;
        this.mon2scb_rd = mon2scb_rd;
        this.cmp_count  = 0;
        this.err_count  = 0;
    endfunction

    function int unsigned pending();
        return mon2scb_wr.num();
    endfunction

    task run();
        transaction exp_tr;
        transaction act_tr;
        forever begin
            mon2scb_rd.get(act_tr);
            if (!mon2scb_wr.try_get(exp_tr)) begin
                err_count++;
                $error("[%0t] read with no expected data, got %h", $time, act_tr.data);
            end
            else begin
                cmp_count++;
                if (exp_tr.data !== act_tr.data) begin
                    err_count++;
                    $error("[%0t] mismatch exp=%h got=%h", $time, exp_tr.data, act_tr.data);
                end
            end
        end
    endtask
endclass


class environment;
    virtual cdc_if         vif;
    generator              gen;
    driver                 drv;
    monitor                mon;
    scoreboard             scb;
    mailbox #(transaction) gen2drv;
    mailbox #(transaction) mon2scb_wr;
    mailbox #(transaction) mon2scb_rd;

    function new(virtual cdc_if vif);
        this.vif   = vif;
        gen2drv    = new();
        mon2scb_wr = new();
        mon2scb_rd = new();
        gen        = new(gen2drv);
        mon        = new(vif, mon2scb_wr, mon2scb_rd);
        drv        = new(vif, gen2drv, mon);
        scb        = new(mon2scb_wr, mon2scb_rd);
    endfunction

    task pre_test();
        vif.reset = 1'b0;
        repeat (5) @(posedge vif.wclk);
        repeat (5) @(posedge vif.rclk);
        @(posedge vif.wclk);
        vif.reset = 1'b1;
        repeat (5) @(posedge vif.wclk);
        repeat (5) @(posedge vif.rclk);
    endtask

    task test();
        fork
            drv.run();
            mon.run();
            scb.run();
        join_none
    endtask

    task post_test();
        while (gen2drv.num() != 0 || drv.busy) @(posedge vif.wclk);
        repeat (40) @(posedge vif.rclk);
        while (scb.pending() != 0) @(posedge vif.rclk);
        repeat (10) @(posedge vif.rclk);
    endtask

    function void report();
        $display("sent=%0d writes=%0d reads=%0d compared=%0d errors=%0d pending=%0d",
                 gen.sent, mon.wr_count, mon.rd_count, scb.cmp_count, scb.err_count, scb.pending());
        if (scb.err_count == 0 && scb.pending() == 0 &&
            mon.wr_count == mon.rd_count && mon.wr_count == gen.sent)
            $display("PASS");
        else
            $display("FAIL");
    endfunction

    task run();
        pre_test();
        test();
    endtask
endclass


class test;
    environment env;

    function new(virtual cdc_if vif);
        env = new(vif);
    endfunction

    task phase_fill();
        env.drv.r_enable = 1'b0;
        env.gen.gap_max  = 0;
        env.gen.run(30);
        wait (env.mon.wr_count == 16);
        repeat (20) @(posedge env.vif.wclk);
        @(env.vif.wmon_cb);

        if (env.mon.wr_count != 16) begin
            env.scb.err_count++;
            $error("[%0t] fill: expected 16 accepted writes, got %0d", $time, env.mon.wr_count);
        end

        if (env.vif.wmon_cb.data_in_ready !== 1'b0) begin
            env.scb.err_count++;
            $error("[%0t] fill: data_in_ready should be low when the FIFO is full", $time);
        end

        if (env.mon.rd_count != 0) begin
            env.scb.err_count++;
            $error("[%0t] fill: reader was stalled but %0d words were read", $time, env.mon.rd_count);
        end
    endtask

    task phase_drain();
        env.drv.r_enable    = 1'b1;
        env.drv.r_ready_pct = 100;
        wait (env.mon.rd_count == 30);
        repeat (20) @(posedge env.vif.rclk);
    endtask

    task phase_random(input int unsigned num);
        env.drv.r_enable    = 1'b1;
        env.drv.r_ready_pct = 50;
        env.gen.gap_max     = 3;
        env.gen.run(num);
    endtask

    task run();
        env.run();
        phase_fill();
        $display("[%0t] fill done: wr=%0d rd=%0d", $time, env.mon.wr_count, env.mon.rd_count);
        phase_drain();
        $display("[%0t] drain done: wr=%0d rd=%0d", $time, env.mon.wr_count, env.mon.rd_count);
        phase_random(200);
        $display("[%0t] random queued", $time);
        env.post_test();
        $display("[%0t] post_test done", $time);
        env.report();
    endtask
endclass


module cdc_tb;

    localparam real WCLK_PERIOD = 10.0;
    localparam real RCLK_PERIOD = 13.0;
    localparam int  TIMEOUT_NS  = 90000;

    logic wclk = 1'b0;
    logic rclk = 1'b0;

    always #(WCLK_PERIOD/2.0) wclk = ~wclk;
    always #(RCLK_PERIOD/2.0) rclk = ~rclk;

    cdc_if intf (.wclk(wclk), .rclk(rclk));

    cdc_top dut (
        .rclk           (rclk),
        .wclk           (wclk),
        .reset          (intf.reset),
        .data_out_valid (intf.data_out_valid),
        .data_out_r     (intf.data_out_r),
        .data_out_ready (intf.data_out_ready),
        .data_in_w      (intf.data_in_w),
        .data_in_valid  (intf.data_in_valid),
        .data_in_ready  (intf.data_in_ready)
    );

    property p_wgray_one_bit;
        @(posedge wclk) disable iff (!intf.reset)
        $countones(dut.wp.wgray_r ^ $past(dut.wp.wgray_r)) <= 1;
    endproperty
    a_wgray_one_bit: assert property (p_wgray_one_bit);

    property p_rgray_one_bit;
        @(posedge rclk) disable iff (!intf.reset)
        $countones(dut.rp.rgray_r ^ $past(dut.rp.rgray_r)) <= 1;
    endproperty
    a_rgray_one_bit: assert property (p_rgray_one_bit);

    property p_no_write_when_full;
        @(posedge wclk) disable iff (!intf.reset)
        dut.wp.full_f |-> !(intf.data_in_valid && intf.data_in_ready);
    endproperty
    a_no_write_when_full: assert property (p_no_write_when_full);

    test t;

    initial begin
        t = new(intf);
        t.run();
        $finish;
    end

    initial begin
        #(TIMEOUT_NS);
        $display("TIMEOUT");
        t.env.report();
        $finish;
    end

endmodule