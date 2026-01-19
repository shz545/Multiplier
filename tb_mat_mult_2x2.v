//pipeline mode testbench for 2x2 matrix multiplication module
`timescale 1ns/1ps

module tb_mat_mult_2x2;

    reg clk;
    reg reset;
    reg start;
    reg signed [15:0] a,b,c,d,e,f,g,h;

    wire signed [31:0] w,x,y,z;
    wire done;

    reg signed [31:0] exp_w, exp_x, exp_y, exp_z;

    integer i;
    integer err_count = 0;

    mat_mult_2x2 u_dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .a(a), .b(b), .c(c), .d(d),
        .e(e), .f(f), .g(g), .h(h),
        .w(w), .x(x), .y(y), .z(z),
        .done(done)
    );

    // 產生時脈 (週期 10ns -> 100MHz)
    always #5 clk = ~clk;
    
    // 預期結果佇列 (Expected Result Queue)
    reg signed [31:0] q_exp_w [0:19];
    reg signed [31:0] q_exp_x [0:19];
    reg signed [31:0] q_exp_y [0:19];
    reg signed [31:0] q_exp_z [0:19];
    integer q_head = 0; // 讀取指標
    integer q_tail = 0; // 寫入指標
    integer check_count = 0; // 已檢查筆數

    // --- Driver Process ---
    reg signed [15:0] t_a, t_b, t_c, t_d, t_e, t_f, t_g, t_h;

    initial begin
        clk = 0;
        reset = 1;
        start = 0;
        a = 0; b = 0; c = 0; d = 0;
        e = 0; f = 0; g = 0; h = 0;
        q_head = 0; q_tail = 0; check_count = 0; err_count = 0;

        $fsdbDumpfile("mat_mult_2x2.fsdb");
        $fsdbDumpvars(0, tb_mat_mult_2x2);

        `ifdef SDF
            $sdf_annotate("./Netlist/mat_mult_2x2.sdf", u_dut);
        `endif

        #10 reset = 0;

        $display("=== Simulation Start (Pipeline Mode) ===");
        
        // Pipeline Filling Phase
        for(i = 0; i < 10; i = i + 1) begin
            // 隨機產生資料
            t_a = $random % 21; t_b = $random % 21; t_c = $random % 21; t_d = $random % 21;
            t_e = $random % 21; t_f = $random % 21; t_g = $random % 21; t_h = $random % 21;
            
            // 計算 Expected 並存入 Queue
            q_exp_w[q_tail] = t_a * t_e + t_b * t_g;
            q_exp_x[q_tail] = t_a * t_f + t_b * t_h;
            q_exp_y[q_tail] = t_c * t_e + t_d * t_g;
            q_exp_z[q_tail] = t_c * t_f + t_d * t_h;
            q_tail = q_tail + 1;

            // 在 Clock Edge 驅動輸入 (稍微延遲，避免 Hold Time Violation)
            @(posedge clk);
            start <= 1;
            a <= t_a; b <= t_b; c <= t_c; d <= t_d;
            e <= t_e; f <= t_f; g <= t_g; h <= t_h;
        end

        // 停止輸入
        @(posedge clk);
        start <= 0;
        a <= 0; b <= 0; c <= 0; d <= 0;
        e <= 0; f <= 0; g <= 0; h <= 0;
    end

    // --- Monitor Process: Check outputs when done is high ---
    initial begin
        wait(reset == 0);
        
        while(check_count < 10) begin
            @(posedge clk);
            if (done) begin
                if (w !== q_exp_w[q_head] || x !== q_exp_x[q_head] || 
                    y !== q_exp_y[q_head] || z !== q_exp_z[q_head]) begin
                    
                    $display("[ERROR] Test %2d Failed!", check_count);
                    $display("  Expected: [%d %d; %d %d]", q_exp_w[q_head], q_exp_x[q_head], q_exp_y[q_head], q_exp_z[q_head]);
                    $display("  Got:      [%d %d; %d %d]", w, x, y, z);
                    err_count = err_count + 1;
                end else begin
                    $display("[PASS] Test %2d Passed. Output: [%d %d; %d %d]", 
                             check_count, w, x, y, z);
                    $display("  Expected: [%d %d; %d %d]", q_exp_w[q_head], q_exp_x[q_head], q_exp_y[q_head], q_exp_z[q_head]);
                    $display("  Got:      [%d %d; %d %d]", w, x, y, z);
                end
                
                q_head = q_head + 1;
                check_count = check_count + 1;
            end
        end
        
        // Final Report
        $display("-------------------------------------------");
        if (err_count == 0) begin
            $display(" Simulation SUCCESS! All 10 pipeline tests passed.");
        end else begin
            $display(" Simulation FAILED with %d errors.", err_count);
        end
        $display("-------------------------------------------");
        $finish;
    end

endmodule
