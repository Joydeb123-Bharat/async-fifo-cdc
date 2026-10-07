`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.10.2026 19:25:36
// Design Name: 
// Module Name: Read_p
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


module Read_p(
    input               data_out_ready,
    input        [31:0] r_data,
    input        [4:0]  w_gray,
    input               reset, // Active low
    input               rclk,
    output logic [4:0]  r_point,
    output logic [31:0] data_out_r,
    output logic        data_out_valid,
    output logic [4:0]  r_gray
    );
    
    // Read pointer in binary and gray
    logic [4:0] rbin_r,rgray_r; 
    logic [4:0] rbin_c,rgray_c;
    logic r_valid;
    // Empty FLag
    logic empty_f;        
    // Synchronisers  
    logic [4:0] wsync_1,wsync_2,wsync_3;
    
    // Pointer logic
    always_ff@(posedge rclk)
    begin
        if(!reset)
        begin
            rbin_r <= '0;
            rgray_r <= '0;
        end
        else
        begin
            rbin_r <= rbin_c;
            rgray_r <= rgray_c;
        end
    end
    always_comb
    begin
        r_valid = !empty_f;
        if(r_valid && !(wsync_3 == rgray_r))
        begin
            data_out_valid = 1'b1;
            data_out_r = r_data;   
            if(data_out_ready)
            begin
                rbin_c = rbin_r + 1'b1; 
            end
            else
            begin
                rbin_c = rbin_r;
            end
        end
        else
        begin
            data_out_r = '0;
            data_out_valid = '0;  
            rbin_c = rbin_r;  
        end
        rgray_c = rbin_c ^ (rbin_c >> 1);;
        r_gray  = rgray_r;
    end
    
    // Synchroniser Chain
    always_ff@(posedge rclk)
    begin
        if(!reset)
        begin
            wsync_1 <= '0;
            wsync_2 <= '0;
            wsync_3 <= '0;
        end
        else
        begin
            wsync_1 <= w_gray;
            wsync_2 <= wsync_1;
            wsync_3 <= wsync_2;
        end
    end
    
    // Empty Flag logic
    always_ff@(posedge rclk)
    begin
        if(!reset)
        begin
            empty_f <= 1'b1;
        end
        else
        begin
            empty_f <= wsync_3 == rgray_c;
        end
    end
    
    // Fifo Pointer
    always_comb
    begin
        r_point = rbin_r;
    end
endmodule
