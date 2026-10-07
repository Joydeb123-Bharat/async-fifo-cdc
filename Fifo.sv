`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.10.2026 20:49:12
// Design Name: 
// Module Name: Fifo
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


module Fifo(
    // Read Port Interface
    input [4:0] r_point,
    output logic [31:0] r_data,
    // Write Port Interface
    input wclk,
    input [31:0] wdata,
    input [4:0]w_point,
    input w_valid
    );
    // Fifo
    logic [31:0] fifo [0:15];
    
    // Write Port
    always_ff@(posedge wclk)
    begin
        if(w_valid)
            fifo[w_point[3:0]] <= wdata;
    end
    
    // Read Port
    always_comb
    begin
        r_data = fifo[r_point[3:0]];
    end    
endmodule
