`timescale 1ns/1ps

module tb_mat_mult_2x2fsm;

    reg clk;
    reg reset;
    reg start;
    reg signed [15:0] a,b,c,d,e,f,g,h;

    wire signed [31:0] w,x,y,z;
    wire done;

    // Expected values
    reg signed [31:0] exp_w, exp_x, exp_y, exp_z;

    integer i;
    integer err_count = 0;

    mat_mult_2x2fsm u_dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .a(a), .b(b), .c(c), .d(d),
        .e(e), .f(f), .g(g), .h(h),
        .w(w), .x(x), .y(y), .z(z),
        .done(done)
    );

    // Generate Clock sequence (Period 10ns -> 100MHz)
    always #5 clk = ~clk;
    
    // Test Driver logic
    reg signed [15:0] t_a, t_b, t_c, t_d, t_e, t_f, t_g, t_h;

    initial begin
        // Init
        clk = 0;
        reset = 1;
        start = 0;
        a = 0; b = 0; c = 0; d = 0;
        e = 0; f = 0; g = 0; h = 0;
        err_count = 0;

      $fsdbDumpfile("mat_mult_2x2fsm.fsdb");
      $fsdbDumpvars(0, tb_mat_mult_2x2fsm);

        `ifdef SDF
            $sdf_annotate("./Netlist/mat_mult_2x2fsm.sdf", u_dut);
        `endif

        // Reset Pulse
        #10 reset = 0;

        $display("=== Simulation Start (FSM Mode) ===");
        
        // Loop for 10 test cases
        for(i = 0; i < 10; i = i + 1) begin
            // 1. Generate Random Data
            t_a = $random % 21; t_b = $random % 21; t_c = $random % 21; t_d = $random % 21;
            t_e = $random % 21; t_f = $random % 21; t_g = $random % 21; t_h = $random % 21;
            
            // 2. Calculate Expected Results locally
            exp_w = t_a * t_e + t_b * t_g;
            exp_x = t_a * t_f + t_b * t_h;
            exp_y = t_c * t_e + t_d * t_g;
            exp_z = t_c * t_f + t_d * t_h;

            // 3. Drive Inputs
            @(posedge clk);
            start <= 1;
            a <= t_a; b <= t_b; c <= t_c; d <= t_d;
            e <= t_e; f <= t_f; g <= t_g; h <= t_h;

            // 4. De-assert Start
            @(posedge clk);
            start <= 0;
            // Clear inputs just to be safe (optional)
            a <= 0; b <= 0; c <= 0; d <= 0;
            e <= 0; f <= 0; g <= 0; h <= 0;

            // 5. Wait for Done
            wait(done);
            @(negedge clk); // Critical: Wait for data bus to settle in Gate Sim

            // 6. Check Results
            if (w !== exp_w || x !== exp_x || y !== exp_y || z !== exp_z) begin
                $display("[ERROR] Test %2d Failed!", i);
                $display("  Inputs:   A=[%d %d; %d %d], B=[%d %d; %d %d]", 
                         t_a, t_b, t_c, t_d, t_e, t_f, t_g, t_h);
                $display("  Expected: [%d %d; %d %d]", exp_w, exp_x, exp_y, exp_z);
                $display("  Got:      [%d %d; %d %d]", w, x, y, z);
                err_count = err_count + 1;
            end else begin
                $display("[PASS] Test %2d Passed. Output: [%d %d; %d %d]", i, w, x, y, z);
                $display("  Inputs:   A=[%d %d; %d %d], B=[%d %d; %d %d]", 
                         t_a, t_b, t_c, t_d, t_e, t_f, t_g, t_h);
                $display("  Expected: [%d %d; %d %d]", exp_w, exp_x, exp_y, exp_z);
                $display("  Got:      [%d %d; %d %d]", w, x, y, z);
            end
        end

        // Final Report
        $display("-------------------------------------------");
        if (err_count == 0) begin
            $display(" Simulation SUCCESS! All 10 tests passed.");
        end else begin
            $display(" Simulation FAILED with %d errors.", err_count);
        end
        $display("-------------------------------------------");
        $finish;
    end

endmodule
