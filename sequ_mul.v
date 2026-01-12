`timescale 1ns/1ps

// ==========================================================
// 子模組: sequ_mul (序列式移位加法乘法器)
// ==========================================================
module sequ_mul (
    input clock,
    input start,
    input reset,
    input signed [15:0] mlier,
    input signed [15:0] mcand,
    output reg valid,
    output reg signed [32:0] prodt_end
  );
  parameter n = 16;

  localparam IDLE = 2'b00;
  localparam CALC = 2'b01;
  localparam SIGN = 2'b11;
  localparam DONE = 2'b10;

  reg [1:0] current_state, next_state;

  reg [n-1:0] a;         // 被乘數暫存器 (Absolute Value)
  reg [4:0] count;       // 計數器
  reg stored_sign;       // Stores the final sign (XOR of inputs)

  wire [n-1:0] adder_input_b;
  wire [n-1:0] adder_sum;
  wire adder_cout;
  wire [2*n:0] next_prodt_val; // 33 bits (16*2 + 1)
  wire [4:0] next_count;

  // Calculate Absolute Values & Sign
  wire sign_a = mlier[15];
  wire sign_b = mcand[15];
  wire final_sign = sign_a ^ sign_b;
  wire [15:0] abs_mlier = sign_a ? (~mlier + 1'b1) : mlier;
  wire [15:0] abs_mcand = sign_b ? (~mcand + 1'b1) : mcand;

  // 組合計算邏輯
  assign adder_input_b = (prodt_end[0]) ? a : {(n){1'b0}};
  assign {adder_cout, adder_sum} = prodt_end[2*n-1:n] + adder_input_b;
  assign next_prodt_val = {1'b0, adder_cout, adder_sum, prodt_end[n-1:1]};
  assign next_count = count - 1'b1;

  // 下一態邏輯
  always @(*)
  begin
    case (current_state)
      IDLE:
        if (start) next_state = CALC;
        else next_state = IDLE;
      CALC:
        if (count == 1) next_state = SIGN;
        else next_state = CALC;
      SIGN:
        next_state = DONE;
      DONE:
        if (!start) next_state = IDLE;
        else next_state = DONE;
      default:
        next_state = IDLE;
    endcase
  end

  // 循序邏輯
  always @(posedge clock)
  begin
    if (reset)
    begin
      current_state <= IDLE;
      a <= {(n){1'b0}};
      count <= 0;
      prodt_end <= {(2*n+1){1'b0}};
      valid <= 0;
      stored_sign <= 0;
    end
    else
    begin
      current_state <= next_state;
      case (current_state)
        IDLE:
        begin
          valid <= 0;
          if (start) 
          begin
            // 載入初始值 (Absolute Values)
            prodt_end <= { {(n+1){1'b0}}, abs_mlier };
            a <= abs_mcand;
            count <= n;
            stored_sign <= final_sign;
          end
        end
        CALC:
        begin
          prodt_end <= next_prodt_val;
          count <= next_count;
        end
        SIGN:
        begin
           if (stored_sign)
             prodt_end <= ~prodt_end + 1'b1;
        end
        DONE:
        begin
          valid <= 1;
        end
      endcase
    end
  end
endmodule
