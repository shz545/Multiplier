`timescale 1ns / 1ps

module mat_mult_2x2fsmpipe(
    input clk,
    input reset,
    input start,
    input signed [15:0] a,b,c,d,e,f,g,h,
    output reg signed [31:0] w,x,y,z,
    output reg done
);

    // Pipeline Registers
    // Stage 1: Input Latch
    reg signed [15:0] a_s1, b_s1, c_s1, d_s1, e_s1, f_s1, g_s1, h_s1;
    reg valid_s1;

    // Stage 2: Multiplier Output
    reg signed [31:0] ae_s2, bg_s2, af_s2, bh_s2, ce_s2, dg_s2, cf_s2, dh_s2;
    reg valid_s2;

    // Combinational Logic for Multiplication (Input to Stage 2)
    wire signed [31:0] ae_comb, bg_comb, af_comb, bh_comb, ce_comb, dg_comb, cf_comb, dh_comb;
    assign ae_comb = a_s1 * e_s1;
    assign bg_comb = b_s1 * g_s1;
    assign af_comb = a_s1 * f_s1;
    assign bh_comb = b_s1 * h_s1;
    assign ce_comb = c_s1 * e_s1;
    assign dg_comb = d_s1 * g_s1;
    assign cf_comb = c_s1 * f_s1;
    assign dh_comb = d_s1 * h_s1;

    // Combinational Logic for Addition (Stage 2 to Output)
    wire signed [31:0] w_comb, x_comb, y_comb, z_comb;
    assign w_comb = ae_s2 + bg_s2;
    assign x_comb = af_s2 + bh_s2;
    assign y_comb = ce_s2 + dg_s2;
    assign z_comb = cf_s2 + dh_s2;

    // Pipeline Control & Datapath
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            // Reset Control Signals
            valid_s1 <= 0;
            valid_s2 <= 0;
            done <= 0;
            
            // Reset Data Registers
            a_s1 <= 0; b_s1 <= 0; c_s1 <= 0; d_s1 <= 0;
            e_s1 <= 0; f_s1 <= 0; g_s1 <= 0; h_s1 <= 0;
            
            ae_s2 <= 0; bg_s2 <= 0; af_s2 <= 0; bh_s2 <= 0;
            ce_s2 <= 0; dg_s2 <= 0; cf_s2 <= 0; dh_s2 <= 0;
            
            w <= 0; x <= 0; y <= 0; z <= 0;
        end
        else begin
            // --- Stage 1: Input Latch ---
            valid_s1 <= start;
            if(start) begin
                a_s1 <= a; b_s1 <= b; c_s1 <= c; d_s1 <= d;
                e_s1 <= e; f_s1 <= f; g_s1 <= g; h_s1 <= h;
            end

            // --- Stage 2: Multiply ---
            valid_s2 <= valid_s1;
            if(valid_s1) begin
                ae_s2 <= ae_comb;
                bg_s2 <= bg_comb;
                af_s2 <= af_comb;
                bh_s2 <= bh_comb;
                ce_s2 <= ce_comb;
                dg_s2 <= dg_comb;
                cf_s2 <= cf_comb;
                dh_s2 <= dh_comb;
            end
            
            // --- Stage 3: Add & Output ---
            done <= valid_s2;
            if(valid_s2) begin
                w <= w_comb;
                x <= x_comb;
                y <= y_comb;
                z <= z_comb;
            end else begin
                done <= 0;
            end
        end
    end

endmodule
