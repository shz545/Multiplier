`timescale 1ns / 1ps

module mat_mult_direct(
    input clk,
    input reset,
    input start,
    // 記憶體存取介面
    output reg [9:0] addr_a,      // A: 16x49
    input signed [15:0] data_a,   // 從TB讀入
    output reg [10:0] addr_b,     // B: 49x32
    input signed [15:0] data_b,   // 從TB讀入
    output reg [8:0] addr_c,      // C: 16x32
    output reg signed [31:0] data_c,
    output reg we_c,
    output reg done
);

    // 矩陣維度
    parameter ROWS_A = 16;
    parameter COLS_A = 49;
    parameter COLS_B = 32;
    
    // FSM States
    parameter IDLE      = 3'd0;
    parameter CALC_MUL  = 3'd1;
    parameter CALC_ADD  = 3'd2;
    parameter WRITE     = 3'd3;
    parameter DONE      = 3'd4;

    reg [2:0] current_state, next_state;

    // Counters
    reg [4:0] row_i; // 0~15 (Rows of A)
    reg [5:0] col_j; // 0~31 (Cols of B)
    reg [5:0] k; // 0~48 (Common Dim)

    reg signed [31:0] acc_reg;
    reg signed [31:0] mult_reg;

    // Calculation wires
    wire signed [31:0] mult_res_wire;
    wire signed [31:0] acc_next_wire;
    
    wire [5:0] k_plus_1;
    wire [5:0] next_col_j;
    wire [4:0] next_row_i;

    wire [9:0] addr_a_next_k;
    wire [10:0] addr_b_next_k;
    wire [9:0] addr_a_next_row;
    wire [9:0] addr_a_next_col;
    wire [10:0] addr_b_next_col;
    wire [8:0] addr_c_calc;

    assign mult_res_wire = data_a * data_b;
    assign acc_next_wire = acc_reg + mult_reg;
    
    assign k_plus_1 = k + 1;
    assign next_col_j = col_j + 1;
    assign next_row_i = row_i + 1;
    
    // Address calculations
    assign addr_a_next_k   = row_i * COLS_A + k_plus_1;
    assign addr_b_next_k   = k_plus_1 * COLS_B + col_j;
    
    assign addr_a_next_row = next_row_i * COLS_A;
    // addr_b_next_row is just 0

    assign addr_a_next_col = row_i * COLS_A;
    assign addr_b_next_col = next_col_j; // since k=0, addr = 0*32 + j+1
    
    assign addr_c_calc     = row_i * COLS_B + col_j;

    // Next state logic
    always @(*) begin
        case (current_state)
            IDLE: begin
                if (start) next_state = CALC_MUL;
                else next_state = IDLE;
            end
            CALC_MUL: begin
                next_state = CALC_ADD;
            end
            CALC_ADD: begin
                // 當 k 數到最後一個 (48) 時，這是最後一次加法，下一周期寫入
                if (k == COLS_A - 1) next_state = WRITE;
                else next_state = CALC_MUL;
            end
            WRITE: begin
                if (row_i == ROWS_A - 1 && col_j == COLS_B - 1) next_state = DONE;
                else next_state = CALC_MUL;
            end
            DONE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // FSM & Datapath
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= IDLE;
            row_i <= 0; col_j <= 0; k <= 0;
            acc_reg <= 0;
            addr_a <= 0; addr_b <= 0; addr_c <= 0;
            data_c <= 0; we_c <= 0; done <= 0;
        end else begin
            current_state <= next_state;
            we_c <= 0; // default pulse low
            done <= 0;

            case (current_state)
                IDLE: begin
                    row_i <= 0; col_j <= 0; k <= 0;
                    acc_reg <= 0;
                    mult_reg <= 0;
                    done <= 0;
                end

                CALC_MUL: begin
                    // Stage 1: Multiply
                    mult_reg <= mult_res_wire;
                end

                CALC_ADD: begin
                    // Stage 2: Accumulate & Address Update
                    
                    acc_reg <= acc_next_wire;

                    if (k == COLS_A - 1) begin
                        // 算完最後一個了，不用加 k 了，準備跳 WRITE
                    end else begin
                        k <= k_plus_1;
                    end

                    // 預先設定下一個地址 (Pipeline Address)
                    // 如果 k < COLS_A - 1，下一個是 k+1
                    if (k < COLS_A - 1) begin
                        addr_a <= addr_a_next_k;
                        addr_b <= addr_b_next_k;
                    end else begin
                        // 準備下一組 (i, j+1) 或 (i+1, 0) 的 第一個 k=0
                        // 雖然下一狀態是 WRITE，但我們可以先設好 k=0 的地址
                        if (col_j == COLS_B - 1) begin
                             // 下一列
                             if (row_i < ROWS_A - 1) begin
                                 addr_a <= addr_a_next_row;
                                 addr_b <= 0;
                             end
                        end else begin
                             // 下一行
                             addr_a <= addr_a_next_col;
                             addr_b <= addr_b_next_col;
                        end
                    end
                end

                WRITE: begin
                    // 輸出結果
                    data_c <= acc_reg;
                    addr_c <= addr_c_calc;
                    we_c <= 1;
                    
                    // 重置累加器與計數器
                    acc_reg <= 0;
                    k <= 0;

                    // 更新 i, j Loop
                    if (col_j == COLS_B - 1) begin
                        col_j <= 0;
                        if (row_i < ROWS_A - 1) row_i <= next_row_i;
                    end else begin
                        col_j <= next_col_j;
                    end
                end

                DONE: begin
                    done <= 1;
                end
            endcase
            
            // 特殊處理: IDLE -> CALC_MUL 的瞬間，需要送出 k=0 的地址
            if (current_state == IDLE && next_state == CALC_MUL) begin
                addr_a <= 0; // i=0, k=0
                addr_b <= 0; // k=0, j=0
                acc_reg <= 0;
                mult_reg <= 0;
                row_i <= 0; col_j <= 0; k <= 0;
            end
        end
    end

endmodule
