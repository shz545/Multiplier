`timescale 1ns/1ps

module tb_mult_1x1;

    reg signed [15:0] a;
    reg signed [15:0] b;

    // * 修改 1: 這裡必須改成 [31:0] 才能接住完整的乘積
    wire signed [31:0] out;

    integer i;

    mult_1x1 u_dut (
        .a(a),
        .b(b),
        .out(out)
    );

    initial begin
        $fsdbDumpfile("mult_1x1.fsdb");
        $fsdbDumpvars(0, tb_mult_1x1);
        
        a = 0;
        b = 0;
        
        // 如果還沒有做合成，這行 sdf_annotate 可以先註解掉，避免報錯
        $sdf_annotate("Netlist/mult_1x1.sdf", u_dut);

        $display("=== Simulation Start ===");
        #10;
        
        for(i = 0; i < 100; i = i + 1) begin
            // 隨機產生測試資料
            a = $random % 24;
            b = $random % 24;
            // @(posedge clk); // 這裡因為是組合邏輯，不需要等 clk

            #20;
            
            // * 修改 2: 顯示邏輯調整
            // 輸入 A, B 是 Q8.8 (除以 256.0)
            // 輸出 OUT 是 Q16.16 (除以 65536.0) -> 因為 2^8 * 2^8 = 2^16
            $display("Test %0d: a=%f, b=%f, out=%f, (Hex: %h * %h = %h)", 
                i+1,
                $itor(a)/256.0,
                $itor(b)/256.0,
                $itor(out)/65536.0, // 改成除以 65536.0
                a, b, out);
        end

        $display("=== Simulation End ===");
        $finish;
    end

endmodule
