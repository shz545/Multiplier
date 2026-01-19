`timescale 1ns / 1ps

module mat_mult_2x2fsm(
    input clk,
    input reset,
    input start,
    input signed [15:0] a,b,c,d,e,f,g,h,
    output reg signed [31:0] w,x,y,z,
    output reg done
);

    // FSM States
    parameter IDLE = 2'd0;
    parameter S1   = 2'd1; // Muls
    parameter S2   = 2'd2; // Adds
    
    reg [1:0] current_state, next_state;

    // Registers
    reg signed [15:0] a_reg, b_reg, c_reg, d_reg, e_reg, f_reg, g_reg, h_reg;
    reg signed [31:0] ae_reg, bg_reg, af_reg, bh_reg, ce_reg, dg_reg, cf_reg, dh_reg;

    // Combinational Logic Wires
    wire signed [31:0] ae_comb, bg_comb, af_comb, bh_comb, ce_comb, dg_comb, cf_comb, dh_comb;
    wire signed [31:0] w_comb, x_comb, y_comb, z_comb;

    // Combinational Calculations
    assign ae_comb = a_reg * e_reg;
    assign bg_comb = b_reg * g_reg;
    assign af_comb = a_reg * f_reg;
    assign bh_comb = b_reg * h_reg;
    assign ce_comb = c_reg * e_reg;
    assign dg_comb = d_reg * g_reg;
    assign cf_comb = c_reg * f_reg;
    assign dh_comb = d_reg * h_reg;

    assign w_comb = ae_reg + bg_reg;
    assign x_comb = af_reg + bh_reg;
    assign y_comb = ce_reg + dg_reg;
    assign z_comb = cf_reg + dh_reg;

    // Next State Logic
    always @(*) begin
        case(current_state)
            IDLE: begin
                if(start) next_state = S1;
                else next_state = IDLE;
            end
            S1: next_state = S2;
            S2: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // State Register
    always @(posedge clk or posedge reset) begin
        if(reset) current_state <= IDLE;
        else current_state <= next_state;
    end

    // Datapath & Output Logic
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            a_reg <= 0; b_reg <= 0; c_reg <= 0; d_reg <= 0;
            e_reg <= 0; f_reg <= 0; g_reg <= 0; h_reg <= 0;
            ae_reg <= 0; bg_reg <= 0; af_reg <= 0; bh_reg <= 0;
            ce_reg <= 0; dg_reg <= 0; cf_reg <= 0; dh_reg <= 0;
            w <= 0; x <= 0; y <= 0; z <= 0;
            done <= 0;
        end
        else begin
            case(current_state)
                IDLE: begin
                    done <= 0;
                    if(start) begin
                        a_reg <= a; b_reg <= b; c_reg <= c; d_reg <= d;
                        e_reg <= e; f_reg <= f; g_reg <= g; h_reg <= h;
                    end
                end
                S1: begin
                    // Multiplication Stage
                    ae_reg <= ae_comb;
                    bg_reg <= bg_comb;
                    af_reg <= af_comb;
                    bh_reg <= bh_comb;
                    ce_reg <= ce_comb;
                    dg_reg <= dg_comb;
                    cf_reg <= cf_comb;
                    dh_reg <= dh_comb;
                end
                S2: begin
                    // Addition Stage & Output
                    w <= w_comb;
                    x <= x_comb;
                    y <= y_comb;
                    z <= z_comb;
                    done <= 1;
                end
            endcase
        end
    end

endmodule
