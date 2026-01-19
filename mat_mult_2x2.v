//pipeline mode 2x2 matrix multiplication module
`timescale 1ns / 1ps

module mat_mult_2x2(
    input clk,
    input reset,
    input start,
    input signed [15:0] a,b,c,d,e,f,g,h,
    output reg signed [31:0] w,x,y,z,
    output reg done
);

    // Pipeline Valid Signals (shift register for valid)
    // pipe_valid[0]: Stage 1 (Input Latch / MUL Logic) valid
    // pipe_valid[1]: Stage 2 (MUL Latch / ADD Logic) valid
    reg [1:0] pipe_valid;

    // 輸入矩陣暫存器 (Input registers)
    reg signed [15:0] a_reg, b_reg, c_reg, d_reg, e_reg, f_reg, g_reg, h_reg;

    // 中間乘法結果暫存器
    reg signed [31:0] ae_reg, bg_reg, af_reg, bh_reg, ce_reg, dg_reg, cf_reg, dh_reg;

    // 乘法器輸出線路 (Multiplication combination logic)
    wire signed [31:0] ae_comb, bg_comb, af_comb, bh_comb, ce_comb, dg_comb, cf_comb, dh_comb;

    // 加法器輸出線路 (Addition combination logic)
    wire signed [31:0] w_comb, x_comb, y_comb, z_comb;

    // 4. 所有計算使用 assign

    // 乘法運算 (Combinational Logic for Multiplication)
    assign ae_comb = a_reg * e_reg;
    assign bg_comb = b_reg * g_reg;
    assign af_comb = a_reg * f_reg;
    assign bh_comb = b_reg * h_reg;
    assign ce_comb = c_reg * e_reg;
    assign dg_comb = d_reg * g_reg;
    assign cf_comb = c_reg * f_reg;
    assign dh_comb = d_reg * h_reg;

    // 加法運算 (Combinational Logic for Addition)
    // 注意：這裡使用乘法暫存器 (ae_reg 等) 進行加法
    assign w_comb = ae_reg + bg_reg;
    assign x_comb = af_reg + bh_reg;
    assign y_comb = ce_reg + dg_reg;
    assign z_comb = cf_reg + dh_reg;

    // 管線暫存器控制 (Pipeline Registers Control)
    always @(posedge clk or posedge reset)
    begin
        if (reset)
        begin
            pipe_valid <= 0;
            done <= 0;
            
            // 重置資料暫存器 (雖然 Datapath 不一定需要 reset，但為了模擬方便先清空)
            a_reg <= 0; b_reg <= 0; c_reg <= 0; d_reg <= 0;
            e_reg <= 0; f_reg <= 0; g_reg <= 0; h_reg <= 0;
            ae_reg <= 0; bg_reg <= 0; af_reg <= 0; bh_reg <= 0;
            ce_reg <= 0; dg_reg <= 0; cf_reg <= 0; dh_reg <= 0;
            w <= 0; x <= 0; y <= 0; z <= 0;
        end
        else
        begin
            // --- Stage 0 -> Stage 1: Input Latch ---
            // 每個 cycle 都可以吃 start，如果 start 為高，鎖存輸入
            // 若要支援每個 cycle 都有值，則無條件鎖存，或者利用 start 當 valid
            if (start) begin
                a_reg <= a; b_reg <= b; c_reg <= c; d_reg <= d;
                e_reg <= e; f_reg <= f; g_reg <= g; h_reg <= h;
            end
            pipe_valid[0] <= start; // 將 start 訊號往後傳遞

            // --- Stage 1 -> Stage 2: Multiply Latch ---
            // 將乘法組合電路的結果鎖存
            ae_reg <= ae_comb; bg_reg <= bg_comb;
            af_reg <= af_comb; bh_reg <= bh_comb;
            ce_reg <= ce_comb; dg_reg <= dg_comb;
            cf_reg <= cf_comb; dh_reg <= dh_comb;
            
            pipe_valid[1] <= pipe_valid[0]; // 傳遞 Valid 訊號

            // --- Stage 2 -> Stage 3: Output Latch ---
            // 將加法組合電路的結果鎖存至輸出
            w <= w_comb;
            x <= x_comb;
            y <= y_comb;
            z <= z_comb;
            
            done <= pipe_valid[1]; // 最終輸出的 Valid 訊號
        end
    end

endmodule
