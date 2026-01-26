`timescale 1ns / 1ps

module mat_mult_1632(
    input clk,
    input reset,
    input start,
    // 新增記憶體介面
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
    parameter ROWS_A = 16;         // 矩陣A的列數
    parameter COLS_A = 49;         // 矩陣A的行數 (也是矩陣B的列數)
    parameter COLS_B = 32;         // 矩陣B的行數
    parameter BLK_SIZE = 7;        // 每次並行計算的元素個數 (Block Size)
    parameter NUM_BLKS = COLS_A / BLK_SIZE; // 總共需要計算幾個 Block (49/7 = 7)

    // 資料儲存暫存器
    // 內部大型記憶體 (用來儲存整個矩陣，實現快速並行讀取)
    reg signed [15:0] internal_mem_a [0:ROWS_A*COLS_A-1]; // 16*49 = 784 words
    reg signed [15:0] internal_mem_b [0:COLS_A*COLS_B-1]; // 49*32 = 1568 words
    
    // FSM 狀態定義 (對應新版系統圖 + Preload)
    parameter IDLE      = 3'd0;   
    parameter LOAD_DATA = 3'd1;   // [New] 同時預先讀取矩陣 A 和 B
    parameter READ      = 3'd2;   // [state:READ] 這裡現在可以 1個clk 平行讀取7個值！
    parameter MUL       = 3'd3;   // [state:MUL] 7個乘法器
    parameter SUM       = 3'd4;   // [state:SUM] 加法樹
    parameter ACC       = 3'd5;   // [state:ACC] 累加
    parameter WRITE     = 3'd6;   // [state:WRITE] 寫入
    parameter DONE      = 3'd7;   // 完成
    
    reg [2:0] current_state, next_state; // 狀態位元縮減為 3 bits

    // 迴圈與地址計數器
    reg [9:0] load_cnt_a;  // 用於 LOAD_A 的計數器 (0~783)
    reg [10:0] load_cnt_b; // 用於 LOAD_B 的計數器 (0~1567)
    
    reg [4:0] row_i;   // 當前計算到 C 矩陣的第幾列 (0~15)
    reg [5:0] col_j;   // 當前計算到 C 矩陣的第幾行 (0~31)
    reg [2:0] blk_k;   // 當前計算到第幾個 Block (0~6)
    // fetch_i 已經不需要了，因為我們一次讀 7 個

    // 運算用的小暫存器
    reg signed [15:0] a_reg [0:6];       // 暫存 7 個 A 元素
    reg signed [15:0] b_reg [0:6];       // 暫存 7 個 B 元素

    // [New] 補上缺失的 32-bit 運算暫存器宣告
    reg signed [31:0] product_reg [0:6]; // 暫存 7 個乘法結果
    reg signed [31:0] sum_reg;           // 暫存加法樹結果
    reg signed [31:0] acc_reg;           // 累加器

    // 組合邏輯運算
    wire signed [31:0] p0, p1, p2, p3, p4, p5, p6; // 乘法器的輸出接線
    wire signed [31:0] sum_products;               // 加法樹的輸出接線


    assign p0 = a_reg[0] * b_reg[0]; // 並行乘法運算 0
    assign p1 = a_reg[1] * b_reg[1]; // 並行乘法運算 1
    assign p2 = a_reg[2] * b_reg[2]; // 並行乘法運算 2
    assign p3 = a_reg[3] * b_reg[3]; // 並行乘法運算 3
    assign p4 = a_reg[4] * b_reg[4]; // 並行乘法運算 4
    assign p5 = a_reg[5] * b_reg[5]; // 並行乘法運算 5
    assign p6 = a_reg[6] * b_reg[6]; // 並行乘法運算 6

    assign sum_products = product_reg[0] + product_reg[1] + product_reg[2] + product_reg[3] + product_reg[4] + product_reg[5] + product_reg[6]; // 加法樹運算：將 7 個乘積相加

    // 計算 READ 狀態時，從 internal_mem 讀取資料的 Base Index
    wire [9:0] idx_a_base;
    wire [10:0] idx_b_base;
    
    wire [8:0] addr_c_calc;         // 寫入 C 結果時的記憶體地址
    wire signed [31:0] next_acc;    // 計算下一時刻的 acc_reg 值
    
    wire [2:0] next_blk_k;          // 下一個 blk_k 的值
    wire [5:0] next_col_j;          // 下一個 col_j 的值
    wire [4:0] next_row_i;          // 下一個 row_i 的值

    // 計算內部記憶體的讀取索引
    assign idx_a_base = (row_i * COLS_A) + (blk_k * BLK_SIZE);          // A 在列方向上是連續的
    assign idx_b_base = (blk_k * BLK_SIZE) * COLS_B + col_j;            // B 也是 Row-Major，但在行方向上不連續 (Stride = COLS_B)
    
    assign addr_c_calc = row_i * COLS_B + col_j; // 計算寫入 C 矩陣的目標地址

    assign next_acc = acc_reg + sum_reg; // 計算下一時刻的累加結果 (Current Accumulation + Partial Sum)

    assign next_blk_k   = blk_k + 1;   // blk_k 計數器 +1 (下一個 block 索引)
    assign next_col_j   = col_j + 1;   // col_j 計數器 +1 (下一個 Column 索引)
    assign next_row_i   = row_i + 1;   // row_i 計數器 +1 (下一個 Row 索引)

    // [New] 將加法計算拉出來 assign
    wire [9:0] next_load_cnt_a;
    wire [10:0] next_load_cnt_b;
    assign next_load_cnt_a = load_cnt_a + 1;
    assign next_load_cnt_b = load_cnt_b + 1;

    // FSM 時序邏輯
    always @(posedge clk or posedge reset) begin
        if (reset) current_state <= IDLE;
        else current_state <= next_state;
    end

    // FSM 組合邏輯
    always @(*) begin
        case (current_state)
            IDLE: begin
                if (start) next_state = LOAD_DATA;
                else next_state = IDLE;
            end
            
            LOAD_DATA: begin
                // 同時讀取 A (784個) 和 B (1568個)
                // 以較大的 B 矩陣為準
                if (load_cnt_b == COLS_A * COLS_B - 1) next_state = READ;
                else next_state = LOAD_DATA;
            end

            READ: begin
                // 這裡現在只需 1 個 Cycle 即可讀完 7 個值
                next_state = MUL;
            end

            MUL: next_state = SUM;

            SUM: next_state = ACC;

            ACC: begin
                if (blk_k == NUM_BLKS - 1) next_state = WRITE;
                else next_state = READ;
            end

            WRITE: begin
                if (col_j == COLS_B - 1 && row_i == ROWS_A - 1) next_state = DONE;
                else next_state = READ; 
            end

            DONE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // 資料路徑 (Datapath)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            addr_a <= 0; addr_b <= 0; addr_c <= 0;
            data_c <= 0; we_c <= 0; done <= 0;
            row_i <= 0; col_j <= 0; blk_k <= 0;
            load_cnt_a <= 0; load_cnt_b <= 0;
            acc_reg <= 0;
            sum_reg <= 0;
            a_reg[0] <= 0; a_reg[1] <= 0; a_reg[2] <= 0; a_reg[3] <= 0; a_reg[4] <= 0; a_reg[5] <= 0; a_reg[6] <= 0;
            b_reg[0] <= 0; b_reg[1] <= 0; b_reg[2] <= 0; b_reg[3] <= 0; b_reg[4] <= 0; b_reg[5] <= 0; b_reg[6] <= 0;
            product_reg[0] <= 0; product_reg[1] <= 0; product_reg[2] <= 0; product_reg[3] <= 0; product_reg[4] <= 0; product_reg[5] <= 0; product_reg[6] <= 0;
        end else begin
            we_c <= 0; 
            done <= 0;
            
            case (current_state)
                IDLE: begin
                    row_i <= 0; col_j <= 0; done <= 0;
                    load_cnt_a <= 0; load_cnt_b <= 0;
                    acc_reg <= 0; blk_k <= 0; // 重置運算暫存器
                    addr_a <= 0; addr_b <= 0;
                end
                
                LOAD_DATA: begin
                    // 平行載入 A
                     if (load_cnt_a < ROWS_A * COLS_A) begin
                        internal_mem_a[load_cnt_a] <= data_a; // 存入當前讀到的值
                        if (load_cnt_a < ROWS_A * COLS_A - 1) begin
                            load_cnt_a <= next_load_cnt_a; 
                            addr_a <= next_load_cnt_a; // 預備下一個地址
                        end
                    end

                    // 平行載入 B
                    if (load_cnt_b < COLS_A * COLS_B) begin
                        internal_mem_b[load_cnt_b] <= data_b; // 存入當前讀到的值
                        if (load_cnt_b < COLS_A * COLS_B - 1) begin
                            load_cnt_b <= next_load_cnt_b;
                            addr_b <= next_load_cnt_b; // 預備下一個地址
                        end
                    end
                end

                READ: begin
                    // [Parallel Fetch]
                    // 一次性從內部記憶體平行讀取 7 個數據
                    // A 是連續的
                    a_reg[0] <= internal_mem_a[idx_a_base + 0];
                    a_reg[1] <= internal_mem_a[idx_a_base + 1];
                    a_reg[2] <= internal_mem_a[idx_a_base + 2];
                    a_reg[3] <= internal_mem_a[idx_a_base + 3];
                    a_reg[4] <= internal_mem_a[idx_a_base + 4];
                    a_reg[5] <= internal_mem_a[idx_a_base + 5];
                    a_reg[6] <= internal_mem_a[idx_a_base + 6];
                    
                    // B 是不連續的 (Strided by COLS_B = 32)
                    b_reg[0] <= internal_mem_b[idx_b_base + 0];
                    b_reg[1] <= internal_mem_b[idx_b_base + 32];
                    b_reg[2] <= internal_mem_b[idx_b_base + 64];
                    b_reg[3] <= internal_mem_b[idx_b_base + 96];
                    b_reg[4] <= internal_mem_b[idx_b_base + 128];
                    b_reg[5] <= internal_mem_b[idx_b_base + 160];
                    b_reg[6] <= internal_mem_b[idx_b_base + 192];
                end

                MUL: begin
                    // [state:MUL] 7個乘法器 -> product_reg (1 clk)
                    product_reg[0] <= p0;
                    product_reg[1] <= p1;
                    product_reg[2] <= p2;
                    product_reg[3] <= p3;
                    product_reg[4] <= p4;
                    product_reg[5] <= p5;
                    product_reg[6] <= p6;
                end
                
                SUM: begin
                    // [state:SUM] 6個加法器 (加法樹) -> sum_reg (1 clk)
                    sum_reg <= sum_products;
                end

                ACC: begin
                    // [state:ACC] 累加輸出 (acc_reg + sum_reg) -> acc_reg (1 clk)
                    acc_reg <= next_acc;
                    blk_k <= next_blk_k;
                end

                WRITE: begin
                    // [state:WRITE] 輸出結果 -> 記憶體 (1 clk)
                    addr_c <= addr_c_calc;
                    data_c <= acc_reg;
                    we_c <= 1;
                    
                    // 準備下一個元素的計算，歸零累加器 (無條件執行)
                    acc_reg <= 0;
                    blk_k <= 0;

                    if (col_j == COLS_B - 1) begin
                        col_j <= 0;
                        if (row_i < ROWS_A - 1) row_i <= next_row_i;
                    end else begin
                        col_j <= next_col_j;
                    end
                end
                
                DONE: done <= 1;
            endcase
        end
    end
endmodule
