module mult_axb (
    input clk,
    input reset,
    input start,
    input signed [15:0] a,
    input signed [15:0] b,
    output reg signed [31:0] out,
    output reg done
);

    // 定義狀態
    localparam S_IDLE = 1'b0;
    localparam S_CALC = 1'b1;

    reg current_state, next_state;
    reg signed [15:0] a_reg, b_reg;
    wire signed [31:0] product;
    assign product = a_reg * b_reg;

    // 1. 狀態暫存器 (Sequential)
    always @(posedge clk or posedge reset) begin
        if (reset)
            current_state <= S_IDLE;
        else
            current_state <= next_state;
    end

    // 2. 下一個狀態邏輯 (Combinational)
    always @(*) begin
        case (current_state)
            S_IDLE: begin
                if (start)
                    next_state = S_CALC;
                else
                    next_state = S_IDLE;
            end
            S_CALC: begin
                next_state = S_IDLE; // 計算一拍後回到 IDLE
            end
            default: next_state = S_IDLE;
        endcase
    end

    // 3. 資料路徑與輸出邏輯 (Sequential)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            a_reg <= 0;
            b_reg <= 0;
            out   <= 0;
            done  <= 0;
        end else begin
            // 預設 done 為 0，只在完成時拉高
            done <= 0;
            
            case (current_state)
                S_IDLE: begin
                    if (start) begin
                        a_reg <= a;
                        b_reg <= b;
                    end
                end
                
                S_CALC: begin
                    out  <= product;
                    done <= 1'b1;
                end
            endcase
        end
    end

endmodule
