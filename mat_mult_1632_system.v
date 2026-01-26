`timescale 1ns / 1ps

module mat_mult_1632_system(
    input clk,
    input reset,
    input start,
    // 記憶體介面
    output reg [9:0] addr_a, // A: 16x49 words
    input signed [15:0] data_a,
    output reg [10:0] addr_b, // B: 49x32 words
    input signed [15:0] data_b,
    output reg [8:0] addr_c, // C: 16x32 words
    output reg signed [31:0] data_c,
    output reg we_c,
    output reg done
);

    // 參數定義
    // 矩陣維度 -> A: 16x49, B: 49x32, C: 16x32
    parameter [5:0] ROWS_A = 16;     // 矩陣A的列數 (Max 63)
    parameter [6:0] COLS_A = 49;     // 矩陣A的行數 (Max 127)
    parameter [5:0] COLS_B = 32;     // 矩陣B的行數 (Max 63)
    parameter [3:0] BLK_SIZE = 7;    // Block Size
    parameter [3:0] NUM_BLKS = 7;    // 49/7 = 7

    // 資料儲存暫存器
    // 內部記憶體只存 49 個數值 (Row A 和 Col B)
    reg signed [15:0] internal_mem_a [0:48]; // COLS_A-1 (Fixed for array declaration consistency)
    reg signed [15:0] internal_mem_b [0:48]; // COLS_A-1
    
    // FSM 狀態定義
    parameter IDLE       = 4'd0;   
    parameter LOAD_A_B   = 4'd1;   // 同時載入 Row A 和 Col B (換列或初始時)
    parameter LOAD_B     = 4'd2;   // 只載入 Col B (同列換行時)
    parameter READ       = 4'd3;   // 從 internal_mem 讀取
    parameter MUL        = 4'd4;   
    parameter SUM        = 4'd5;   
    parameter ACC        = 4'd6;   
    parameter WRITE      = 4'd7;   // 寫入 C
    parameter DONE       = 4'd8;   
    
    reg [3:0] current_state, next_state;

    // 計數器
    reg [5:0] load_k;  // 載入計數器 (0~49)
    
    reg [4:0] row_i;   // Outer Loop Row (0~15)
    reg [5:0] col_j;   // Outer Loop Col (0~31)
    reg [2:0] blk_k;   // Inner Loop Block (0~6)

    // 運算暫存器
    reg signed [15:0] a_reg [0:6];       
    reg signed [15:0] b_reg [0:6];       
    reg signed [31:0] product_reg [0:6]; 
    reg signed [31:0] sum_reg;           
    reg signed [31:0] acc_reg;           

    // ==================================================
    // 運算過程 assign 區 (所有計算拉出)
    // ==================================================
    
    // 1. Math Units
    wire signed [31:0] p0, p1, p2, p3, p4, p5, p6;
    assign p0 = a_reg[0] * b_reg[0];
    assign p1 = a_reg[1] * b_reg[1];
    assign p2 = a_reg[2] * b_reg[2];
    assign p3 = a_reg[3] * b_reg[3];
    assign p4 = a_reg[4] * b_reg[4];
    assign p5 = a_reg[5] * b_reg[5];
    assign p6 = a_reg[6] * b_reg[6];

    wire signed [31:0] sum_products;
    assign sum_products = product_reg[0] + product_reg[1] + product_reg[2] + product_reg[3] + 
                          product_reg[4] + product_reg[5] + product_reg[6];

    wire signed [31:0] next_acc;
    assign next_acc = acc_reg + sum_reg;

    // 2. Address & Index Calculations
    // 內部記憶體的基本讀取索引 (Base Index)
    wire [5:0] idx_base;
    assign idx_base = blk_k * BLK_SIZE; 
    
    // 外部記憶體載入地址計算
    // A (Row-Major): Row i, element load_k -> Addr = i * 49 + load_k
    // B (Row-Major): Col j, element load_k -> Addr = load_k * 32 + j
    // 這裡計算 "Next" Address 供下一個 Cycle 載入使用
    wire [5:0] next_load_k;
    assign next_load_k = load_k + 1;

    wire [9:0] addr_a_next_load;
    wire [10:0] addr_b_next_load;
    
    assign addr_a_next_load = row_i * COLS_A + next_load_k;
    assign addr_b_next_load = next_load_k * COLS_B + col_j;

    // WRITE 結束後，準備下一次 LOAD (load_k=0) 的首地址
    // 需要用到 next_row_i, next_col_j
    wire [4:0] next_row_i;
    wire [5:0] next_col_j;
    
    assign next_row_i = row_i + 1;
    assign next_col_j = col_j + 1;
    
    // 下一個狀態如果是 LOAD_B (換行不換列): A地址不變(或無所謂)，B地址為 0*32 + (col_j+1)
    wire [10:0] addr_b_start_next_col; 
    assign addr_b_start_next_col = next_col_j; 

    // 下一個狀態如果是 LOAD_A_B (換列): A地址為 (row_i+1)*49 + 0，B地址為 0*32 + 0
    wire [9:0] addr_a_start_next_row; 
    wire [10:0] addr_b_start_next_row; 
    assign addr_a_start_next_row = next_row_i * COLS_A;
    assign addr_b_start_next_row = 0;

    // C 的寫入地址
    wire [8:0] addr_c_calc;
    assign addr_c_calc = row_i * COLS_B + col_j;

    // 3. Counters Next
    wire [2:0] next_blk_k;
    assign next_blk_k = blk_k + 1;


    // ==================================================
    // FSM 時序邏輯
    // ==================================================
    always @(posedge clk or posedge reset) begin
        if (reset) current_state <= IDLE;
        else current_state <= next_state;
    end

    // FSM 組合邏輯
    always @(*) begin
        case (current_state)
            IDLE: begin
                if (start) next_state = LOAD_A_B;
                else next_state = IDLE;
            end
            
            LOAD_A_B: begin
                // 載入新的 Row A 和 Col B
                if (load_k == COLS_A - 1) next_state = READ; 
                else next_state = LOAD_A_B;
            end

            LOAD_B: begin
                // 只載入新的 Col B (沿用舊的 Row A)
                if (load_k == COLS_A - 1) next_state = READ; 
                else next_state = LOAD_B;
            end

            READ: next_state = MUL;

            MUL: next_state = SUM;

            SUM: next_state = ACC;

            ACC: begin
                if (blk_k == NUM_BLKS - 1) next_state = WRITE;
                else next_state = READ;
            end

            WRITE: begin
                // 判斷下一步:
                // 1. 完成所有 (Done)
                // 2. 換下一列 (New Row A -> LOAD_A_B)
                // 3. 換下一行 (Same Row A -> LOAD_B)
                
                if (col_j == COLS_B - 1) begin 
                    if (row_i == ROWS_A - 1) next_state = DONE;
                    else next_state = LOAD_A_B; // Col done, Row increment -> Reload A & B
                end else begin
                    next_state = LOAD_B;        // Col increment -> Reload B only
                end
            end

            DONE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // ==================================================
    // Datapath
    // ==================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            addr_a <= 0; addr_b <= 0; addr_c <= 0;
            data_c <= 0; we_c <= 0; done <= 0;
            row_i <= 0; col_j <= 0; blk_k <= 0;
            load_k <= 0;
            acc_reg <= 0; sum_reg <= 0;
            // Clear registers
            a_reg[0]<=0; a_reg[1]<=0; a_reg[2]<=0; a_reg[3]<=0; a_reg[4]<=0; a_reg[5]<=0; a_reg[6]<=0;
            b_reg[0]<=0; b_reg[1]<=0; b_reg[2]<=0; b_reg[3]<=0; b_reg[4]<=0; b_reg[5]<=0; b_reg[6]<=0;
            product_reg[0]<=0; product_reg[1]<=0; product_reg[2]<=0; product_reg[3]<=0;
            product_reg[4]<=0; product_reg[5]<=0; product_reg[6]<=0;
        end else begin
            we_c <= 0; 
            done <= 0;
            
            case (current_state)
                IDLE: begin
                    row_i <= 0; col_j <= 0; blk_k <= 0;
                    load_k <= 0;
                    acc_reg <= 0;
                    done <= 0;
                    // Prepare Address for first Load (0,0)
                    addr_a <= 0; 
                    addr_b <= 0;
                end
                
                LOAD_A_B: begin
                    // 同時載入 A 和 B
                    if (load_k < COLS_A) begin
                        internal_mem_a[load_k] <= data_a; 
                        internal_mem_b[load_k] <= data_b; 
                        
                        load_k <= next_load_k; 
                        
                        if (load_k < COLS_A - 1) begin
                            addr_a <= addr_a_next_load;
                            addr_b <= addr_b_next_load;
                        end
                    end
                end

                LOAD_B: begin
                    // 只載入 B，A 保持不變
                     if (load_k < COLS_A) begin
                        // internal_mem_a 不變
                        internal_mem_b[load_k] <= data_b; 
                        
                        load_k <= next_load_k; 
                        
                        if (load_k < COLS_A - 1) begin
                            // addr_a 不變
                            addr_b <= addr_b_next_load;
                        end
                    end
                end

                READ: begin
                    // 從 internal_mem 讀取
                    a_reg[0] <= internal_mem_a[idx_base + 0];
                    a_reg[1] <= internal_mem_a[idx_base + 1];
                    a_reg[2] <= internal_mem_a[idx_base + 2];
                    a_reg[3] <= internal_mem_a[idx_base + 3];
                    a_reg[4] <= internal_mem_a[idx_base + 4];
                    a_reg[5] <= internal_mem_a[idx_base + 5];
                    a_reg[6] <= internal_mem_a[idx_base + 6];
                    
                    b_reg[0] <= internal_mem_b[idx_base + 0];
                    b_reg[1] <= internal_mem_b[idx_base + 1];
                    b_reg[2] <= internal_mem_b[idx_base + 2];
                    b_reg[3] <= internal_mem_b[idx_base + 3];
                    b_reg[4] <= internal_mem_b[idx_base + 4];
                    b_reg[5] <= internal_mem_b[idx_base + 5];
                    b_reg[6] <= internal_mem_b[idx_base + 6];
                end

                MUL: begin
                    product_reg[0] <= p0;
                    product_reg[1] <= p1;
                    product_reg[2] <= p2;
                    product_reg[3] <= p3;
                    product_reg[4] <= p4;
                    product_reg[5] <= p5;
                    product_reg[6] <= p6;
                end
                
                SUM: begin
                    sum_reg <= sum_products;
                end

                ACC: begin
                    acc_reg <= next_acc;
                    blk_k <= next_blk_k;
                end

                WRITE: begin
                    addr_c <= addr_c_calc;
                    data_c <= acc_reg;
                    we_c <= 1;
                    
                    // Reset accumulators
                    acc_reg <= 0;
                    blk_k <= 0;
                    load_k <= 0; 

                    // Update Loops and Prepare Next Address
                    if (col_j == COLS_B - 1) begin
                        col_j <= 0;
                        if (row_i < ROWS_A - 1) begin
                            row_i <= next_row_i;
                            // Next is LOAD_A_B (New Row)
                            addr_a <= addr_a_start_next_row;
                            addr_b <= addr_b_start_next_row;
                        end
                    end else begin
                        col_j <= next_col_j;
                        // Next is LOAD_B (Same Row, New Col)
                        // addr_a unchanged
                        addr_b <= addr_b_start_next_col;
                    end
                end
                
                DONE: done <= 1;
            endcase
        end
    end
endmodule


