`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.10.2026 20:57:46
// Design Name: 
// Module Name: cdc_top
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


module cdc_top(
    // Clocks and Reset
    input rclk,
    input wclk,
    input reset,
    // Read Side
    output logic data_out_valid,
    output logic [31:0] data_out_r,
    input data_out_ready,
    // Write Side
    input [31:0] data_in_w,
    input data_in_valid,
    output logic data_in_ready
    );
    // Necessary wires
    logic [4:0] r_gray, w_gray, r_point, w_point;
    logic [31:0] r_data, w_data;
    logic w_valid;
    
    // Modules
    Read_p rp(
        .data_out_ready(data_out_ready),
        .r_data(r_data),
        .w_gray(w_gray),
        .reset(reset),
        .rclk(rclk),
        .r_point(r_point),
        .data_out_r(data_out_r),
        .data_out_valid(data_out_valid),
        .r_gray(r_gray)
    );
    
    write_p wp(
        .wclk(wclk),
        .reset(reset),
        .data_in_w(data_in_w),   
        .data_in_valid(data_in_valid),
        .data_in_ready(data_in_ready),
        .wdata(w_data),
        .wpoint(w_point),
        .wvalid(w_valid),
        .r_gray(r_gray),
        .w_gray(w_gray)
    );
    
    Fifo fifo(
        .r_point(r_point),
        .r_data(r_data),
        .wclk(wclk),
        .wdata(w_data),
        .w_point(w_point),
        .w_valid(w_valid)    
    );
    
endmodule
