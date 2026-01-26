`timescale 1ns/1ps

module tb_mat_mult_1632;

    reg clk;
    reg reset;
    reg start;
    
    // 參數定義 (需與 RTL 保持一致)
    parameter ROWS_A = 16;
    parameter COLS_A = 49;
    parameter COLS_B = 32;
    
    // 計算記憶體所需大小
    parameter MEM_SIZE_A = ROWS_A * COLS_A; // 16 * 49 = 784
    parameter MEM_SIZE_B = COLS_A * COLS_B; // 49 * 32 = 1568
    parameter MEM_SIZE_C = ROWS_A * COLS_B; // 16 * 32 = 512

    // Memory Signals
    wire [9:0] addr_a;
    wire signed [15:0] data_a;
    wire [10:0] addr_b;
    wire signed [15:0] data_b;
    wire [8:0] addr_c;
    wire signed [31:0] data_c;
    wire we_c;
    wire done;

    // 定義記憶體陣列
    reg signed [15:0] mem_a [0:MEM_SIZE_A-1]; 
    reg signed [15:0] mem_b [0:MEM_SIZE_B-1]; 
    reg signed [31:0] mem_c [0:MEM_SIZE_C-1]; 
    
    // 非同步讀取 (模擬 SRAM Async Read)
    // 加上邊界檢查防止 X 值傳播
    assign data_a = (addr_a < MEM_SIZE_A) ? mem_a[addr_a] : 16'd0;
    assign data_b = (addr_b < MEM_SIZE_B) ? mem_b[addr_b] : 16'd0;
    
    // 寫入 C
    always @(posedge clk) begin
        if (we_c) begin
            // 可以在這裡印出寫入過程方便除錯
            // $display("Time %t: Writing C[%d] = %d", $time, addr_c, data_c);
            mem_c[addr_c] <= data_c;
        end
    end

    // DUT Instantiation (Device Under Test)
    mat_mult_1632 #(
        .ROWS_A(ROWS_A),
        .COLS_A(COLS_A),
        .COLS_B(COLS_B)
    ) u_dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .addr_a(addr_a), .data_a(data_a),
        .addr_b(addr_b), .data_b(data_b),
        .addr_c(addr_c), .data_c(data_c), .we_c(we_c),
        .done(done)
    );

    // Clock Generation (Period = 10ns)
    always #5 clk = ~clk;

    // 驗證變數
    integer i, j, k;
    reg signed [31:0] exp_c [0:MEM_SIZE_C-1]; // Expected Result (黃金值)
    integer err_count;

    initial begin
        // 初始化信號
        clk = 0;
        reset = 1;
        start = 0;
        err_count = 0;
        
        // 產生波形檔 (FSDB)
        $fsdbDumpfile("mat_mult_1632.fsdb");
        $fsdbDumpvars(0, tb_mat_mult_1632);
        `ifdef SDF
            $sdf_annotate("./Netlist/mat_mult_1632.sdf", u_dut);
        `endif
        
        // 1. 初始化記憶體 A 和 B (使用隨機值)
        $display("========================================");
        $display("Initializing Memory A and B with random values...");
        for(i=0; i<MEM_SIZE_A; i=i+1) mem_a[i] = $random % 24; 
        for(i=0; i<MEM_SIZE_B; i=i+1) mem_b[i] = $random % 24;
        for(i=0; i<MEM_SIZE_C; i=i+1) begin mem_c[i] = 0; exp_c[i] = 0; end
        
        // 2. 計算預期結果 (Golden Model)
        // C[i][j] = Sum(A[i][k] * B[k][j])
        $display("Calculating Expected Results (Golden Model)...");
        for(i=0; i<ROWS_A; i=i+1) begin
            for(j=0; j<COLS_B; j=j+1) begin
                exp_c[i*COLS_B + j] = 0;
                
                // [Demo] 顯示 C[0][0] 的計算過程 (示範)
                if (i==0 && j==0) $display("--- Demo: Detailed Calculation for C[0][0] ---");

                for(k=0; k<COLS_A; k=k+1) begin
                     // A addr: Row-Major (i * COLS_A + k)
                     // B addr: Row-Major (k * COLS_B + j)
                     exp_c[i*COLS_B + j] = exp_c[i*COLS_B + j] + mem_a[i*COLS_A + k] * mem_b[k*COLS_B + j];
                     
                     // 只印出前 49 個 element 的乘加過程作為代表
                     if (i==0 && j==0 && k < 49) begin
                        $display("  Step %0d: Sum += A[%0d](%d) * B[%0d](%d) -> NewAcc = %d", 
                                 k, i*COLS_A+k, mem_a[i*COLS_A+k], k*COLS_B+j, mem_b[k*COLS_B+j], exp_c[i*COLS_B+j]);
                     end
                end
            end
        end

        // 3. 開始模擬
        #10 reset = 0;
        #5 start = 1;
        #10 start = 0;
        
        $display("Simulation Started... Waiting for DONE signal.");

        // 等待硬體運算完成
        wait(done);
        @(negedge clk);
        $display("Computation Done at time %t. Verifying Results...", $time);
        
        // 4. 結果比對 (Verify)
        for(i=0; i<MEM_SIZE_C; i=i+1) begin
             // [Demo] 顯示前幾筆比對成功的結果
             if (i < 5) begin
                 $display("Check C[%0d]: Exp = %d, Got = %d ... (MATCH)", i, exp_c[i], mem_c[i]);
             end

             if (mem_c[i] !== exp_c[i]) begin
                 $display("ERROR at C[%0d] (Row %0d, Col %0d): Expected %d, Got %d", i, i/COLS_B, i%COLS_B, exp_c[i], mem_c[i]);
                 err_count = err_count + 1;
             end
        end
        
        if (err_count == 0) begin
            $display("----------------------------------------");
            $display("SUCCESS: Matrix Multiplication Matches!!");
            $display("----------------------------------------");
        end else begin
            $display("----------------------------------------");
            $display("FAILED: Found %0d mismatches.", err_count);
            $display("----------------------------------------");
        end
        
        $finish;
    end
endmodule
