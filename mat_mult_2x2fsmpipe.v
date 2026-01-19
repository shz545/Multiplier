`timescale 1ns / 1ps

module mat_mult_2x2fsmpipe(
    input clk,
    input reset,
    input start,
    input signed [15:0] a,b,c,d,e,f,g,h,
    output reg signed [31:0] w,x,y,z,
    output reg done
);

    // FSM States Definition (Encoding corresponds to {valid_s2, valid_s1})
    // bit 0: Stage 1 has valid data
    // bit 1: Stage 2 has valid data
    parameter IDLE  = 2'b00; // Pipeline Empty
    parameter FILL  = 2'b01; // Only Stage 1 valid
    parameter DRAIN = 2'b10; // Only Stage 2 valid
    parameter FULL  = 2'b11; // Both Stages valid

    reg [1:0] current_state, next_state;

    // Pipeline Registers
    // Stage 1: Input Latch
    reg signed [15:0] a_s1, b_s1, c_s1, d_s1, e_s1, f_s1, g_s1, h_s1;

    // Stage 2: Multiplier Output
    reg signed [31:0] ae_s2, bg_s2, af_s2, bh_s2, ce_s2, dg_s2, cf_s2, dh_s2;

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

    // FSM Next State Logic
    always @(*) begin
        case(current_state)
            IDLE: begin
                if (start) next_state = FILL;
                else       next_state = IDLE;
            end
            FILL: begin
                if (start) next_state = FULL;  // New data in, S1 moves to S2
                else       next_state = DRAIN; // No new data, S1 moves to S2
            end
            DRAIN: begin
                if (start) next_state = FILL;  // New data in, S2 leaves, S1 fills
                else       next_state = IDLE;  // No new data, S2 leaves
            end
            FULL: begin
                if (start) next_state = FULL;  // Keep full
                else       next_state = DRAIN; // Draining
            end
            default: next_state = IDLE;
        endcase
    end

    // Pipeline Control & Datapath
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            // Reset FSM
            current_state <= IDLE;
            done <= 0;
            
            // Reset Data Registers
            a_s1 <= 0; b_s1 <= 0; c_s1 <= 0; d_s1 <= 0;
            e_s1 <= 0; f_s1 <= 0; g_s1 <= 0; h_s1 <= 0;
            
            ae_s2 <= 0; bg_s2 <= 0; af_s2 <= 0; bh_s2 <= 0;
            ce_s2 <= 0; dg_s2 <= 0; cf_s2 <= 0; dh_s2 <= 0;
            
            w <= 0; x <= 0; y <= 0; z <= 0;
        end
        else begin
            // Update State
            current_state <= next_state;

            // --- Stage 1: Input Latch Control ---
            // Dependent on 'start' signal
            if(start) begin
                a_s1 <= a; b_s1 <= b; c_s1 <= c; d_s1 <= d;
                e_s1 <= e; f_s1 <= f; g_s1 <= g; h_s1 <= h;
            end

            // --- Stage 2: Multiply Control ---
            // Enable if current Stage 1 is valid (bit 0 of current state)
            if(current_state[0]) begin
                ae_s2 <= ae_comb;
                bg_s2 <= bg_comb;
                af_s2 <= af_comb;
                bh_s2 <= bh_comb;
                ce_s2 <= ce_comb;
                dg_s2 <= dg_comb;
                cf_s2 <= cf_comb;
                dh_s2 <= dh_comb;
            end
            
            // --- Stage 3: Add & Output Control ---
            // Output valid if current Stage 2 is valid (bit 1 of current state)
            // Note: done logic is effectively the 'valid out' of the pipeline
            done <= current_state[1]; 
            
            if(current_state[1]) begin
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
