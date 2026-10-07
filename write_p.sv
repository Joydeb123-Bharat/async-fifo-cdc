`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.10.2026 19:07:17
// Design Name: 
// Module Name: write_p
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


module write_p(
    // Clock and reset
    input wclk,
    input reset,
    // Data In port
    input [31:0] data_in_w,
    input        data_in_valid,
    output logic data_in_ready,
    // Fifo port
    output logic [31:0] wdata,
    output logic [4:0]  wpoint,
    output logic        wvalid,
    // Read Port Sync and Out
    input        [4:0]  r_gray,
    output logic [4:0]  w_gray
    );
    // Full flag
    logic full_f;
    //Pointers
    logic [4:0] wbin_r, wgray_r;
    logic [4:0] wbin_c, wgray_c;
    // Synchronisers
    logic [4:0] rsync_1,rsync_2,rsync_3;
    
    // Data In Port and Fifo port Logic
    always_ff@(posedge wclk)
    begin
        if(!reset)
        begin
            full_f <= '0;
        end
        else
        begin
            full_f <= (rsync_3 == {~wgray_c[4],~wgray_c[3],wgray_c[2:0]});
        end
    end
    always_comb
    begin
        data_in_ready = ~full_f;
        if(!full_f)
        begin
            wdata = data_in_w;
            wpoint= wbin_r;
            wvalid= data_in_valid;
        end
        else
        begin
            wdata = '0;
            wpoint= '0;
            wvalid= '0;
        end
    end
    
    // Pointer Logic
    always_ff@(posedge wclk)
    begin
        if(!reset)
        begin
            wbin_r <= '0;
            wgray_r<= '0;  
        end
        else
        begin
            wbin_r <= wbin_c;
            wgray_r <= wgray_c;
        end
    end
    always_comb
    begin
        if(data_in_valid && !full_f && !(rsync_3 == {~wgray_r[4],~wgray_r[3],wgray_r[2:0]}))
        begin
            wbin_c = wbin_r + 1'b1;
            wgray_c= wbin_c ^ wbin_c >> 1; 
        end
        else
        begin
            wbin_c = wbin_r;
            wgray_c= wgray_r;    
        end
        w_gray = wgray_r;
    end
    
    // Synchronisers
    always_ff@(posedge wclk)
    begin
        if(!reset)
        begin
           rsync_1 <= '0;
           rsync_2 <= '0;
           rsync_3 <= '0;
        end
        else
        begin
           rsync_1 <= r_gray;
           rsync_2 <= rsync_1;
           rsync_3 <= rsync_2;
        end
    end
endmodule
