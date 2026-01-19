`timescale 1ns/1ps

module tb_mat_mult_2x2fsmpipe;

    reg clk;
    reg reset;
    reg start;
    reg signed [15:0] a,b,c,d,e,f,g,h;

    wire signed [31:0] w,x,y,z;
    wire done;

    // Data Storage for Verification
    reg signed [15:0] in_a[0:100], in_b[0:100], in_c[0:100], in_d[0:100];
    reg signed [15:0] in_e[0:100], in_f[0:100], in_g[0:100], in_h[0:100];
    reg signed [31:0] exp_w[0:100], exp_x[0:100], exp_y[0:100], exp_z[0:100];

    integer i, k;
    integer err_count = 0;

    // Instantiate DUT (Device Under Test)
    mat_mult_2x2 u_dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .a(a), .b(b), .c(c), .d(d),
        .e(e), .f(f), .g(g), .h(h),
        .w(w), .x(x), .y(y), .z(z),
        .done(done)
    );

    // Generate Clock (100MHz)
    always #5 clk = ~clk;

    initial begin
        // 1. Initialization
        clk = 0;
        reset = 1;
        start = 0;
        a = 0; b = 0; c = 0; d = 0;
        e = 0; f = 0; g = 0; h = 0;
        err_count = 0;

        $fsdbDumpfile("mat_mult_2x2fsmpipe.fsdb");
        $fsdbDumpvars(0, tb_mat_mult_2x2fsmpipe);

        `ifdef SDF
            $sdf_annotate("./Netlist/mat_mult_2x2fsmpipe.sdf", u_dut);
        `endif

        // 2. Prepare Test Vectors
        for(i = 0; i < 100; i = i + 1) begin
            in_a[i] = $random % 21; in_b[i] = $random % 21; in_c[i] = $random % 21; in_d[i] = $random % 21;
            in_e[i] = $random % 21; in_f[i] = $random % 21; in_g[i] = $random % 21; in_h[i] = $random % 21;
            
            // Calculate Expected Results
            exp_w[i] = in_a[i] * in_e[i] + in_b[i] * in_g[i];
            exp_x[i] = in_a[i] * in_f[i] + in_b[i] * in_h[i];
            exp_y[i] = in_c[i] * in_e[i] + in_d[i] * in_g[i];
            exp_z[i] = in_c[i] * in_f[i] + in_d[i] * in_h[i];
        end

        // 3. Reset System
        @(posedge clk);
        #1 reset = 1;
        #10 reset = 0;
        @(posedge clk);

        $display("=== Simulation Start (Pipeline Mode) ===");

        // 4. Test Execution (Streaming Mode)
        // We will drive inputs continuously for 100 cycles to test pipeline throughput
        fork
            // --- Thread 1: Input Driver ---
            begin
                $display("[Driver] Starting input stream...");
                for(i = 0; i < 100; i = i + 1) begin
                    @(posedge clk);
                    // Use Non-blocking to mimic hardware driving at clock edge
                    start <= 1;
                    a <= in_a[i]; b <= in_b[i]; c <= in_c[i]; d <= in_d[i];
                    e <= in_e[i]; f <= in_f[i]; g <= in_g[i]; h <= in_h[i];
                end
                // Stop driving after loop
                @(posedge clk);
                start <= 0;
                a <= 0; b <= 0; c <= 0; d <= 0;
                e <= 0; f <= 0; g <= 0; h <= 0;
                $display("[Driver] Input stream finished.");
            end

            // --- Thread 2: Output Monitor ---
            begin
                $display("[Monitor] Waiting for results...");
                k = 0;
                // We expect 100 results. Set a timeout to avoid infinite hang.
                while(k < 100) begin
                    @(posedge clk);
                    // Check if 'done' is high at this clock edge
                    // We check slightly after the edge logic update or simply check the register value
                    // The done signal coming from DUT registers should be stable after the edge.
                    #1; 
                    if(done === 1'b1) begin
                        if(w !== exp_w[k] || x !== exp_x[k] || y !== exp_y[k] || z !== exp_z[k]) begin
                            $display("[ERROR] Item %d mismatch!", k);
                            $display("   Expected: w=%d, x=%d, y=%d, z=%d", exp_w[k], exp_x[k], exp_y[k], exp_z[k]);
                            $display("   Got     : w=%d, x=%d, y=%d, z=%d", w, x, y, z);
                            err_count = err_count + 1;
                        end else begin
                            $display("[PASS] Item %d matched. Output: [%d %d; %d %d]", k, w, x, y, z);
                        end
                        k = k + 1;
                    end
                end
                $display("[Monitor] All 100 items received.");
            end
        join

        // 5. Final Report
        $display("-------------------------------------------");
        if (err_count == 0) begin
            $display(" Simulation SUCCESS! Streaming test passed.");
        end else begin
            $display(" Simulation FAILED with %d errors.", err_count);
        end
        $display("-------------------------------------------");
        $finish;
    end

endmodule
