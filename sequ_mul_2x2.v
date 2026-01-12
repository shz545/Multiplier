`timescale 1ns / 1ps

module sequ_mul_2x2(
    input wire clk,
    input wire reset,
    input wire start,
    input wire[15:0] a,b,c,d,e,f,g,h,
    output reg valid,
    output reg[31:0] w,x,y,z
  );

  // 輸入矩陣暫存器 (Input registers)
  reg [15:0] a_reg, b_reg, c_reg, d_reg, e_reg, f_reg, g_reg, h_reg;

  // 乘法器輸出信號
  wire [32:0] p_raw, q_raw, r_raw, s_raw, t_raw, u_raw, v_raw, k_raw; // sequ_mul 輸出為 33 位元
  wire [31:0] p, q, r, s, t, u, v, k;
  
  // 來自每個乘法器的 valid 信號
  wire v1, v2, v3, v4, v5, v6, v7, v8;
  wire all_valid;

  // 截斷/調整 sequ_mul 的輸出 (33 bits -> 32 bits)
  // sequ_mul 回傳 33 bits (第 32 位元可能是進位/溢位或符號擴充，視設計而定)
  // 這裡假設標準 16x16 -> 32 的乘積位於低位元，以便進行整合
  assign p = p_raw[31:0];
  assign q = q_raw[31:0];
  assign r = r_raw[31:0];
  assign s = s_raw[31:0];
  assign t = t_raw[31:0];
  assign u = u_raw[31:0];
  assign v = v_raw[31:0];
  assign k = k_raw[31:0];

  assign all_valid = v1 & v2 & v3 & v4 & v5 & v6 & v7 & v8;

  // 輸入資料鎖存與輸出控制
  always @(posedge clk or posedge reset)
  begin
    if (reset)
    begin
      a_reg <= 0; b_reg <= 0; c_reg <= 0; d_reg <= 0; 
      e_reg <= 0; f_reg <= 0; g_reg <= 0; h_reg <= 0;
      valid <= 0;
      w <= 0; x <= 0; y <= 0; z <= 0;
    end
    else
    begin
      if (start) begin
         // 當 start 訊號拉起時，鎖存輸入資料
         a_reg <= a; b_reg <= b; c_reg <= c; d_reg <= d;
         e_reg <= e; f_reg <= f; g_reg <= g; h_reg <= h;
         valid <= 0; // 新運算開始時，清除 valid 訊號
      end
      else if (all_valid) begin
         // 當所有乘法器完成運算後，更新輸出
         w <= p + q;
         x <= r + s;
         y <= t + u;
         z <= v + k;
         valid <= 1;
      end
      else begin
         valid <= 0; // 當不是剛做完的那一個 cycle 時，將 valid 拉低
      end
      // 保持輸出的 w, x, y, z 直到下一次運算完成
    end
  end
  
  reg start_d;
  always @(posedge clk or posedge reset) begin
    if(reset) start_d <= 0;
    else start_d <= start;
  end

  sequ_mul m1(.clock(clk), .reset(reset), .start(start_d), .mlier(a_reg), .mcand(e_reg), .valid(v1), .prodt_end(p_raw));
  sequ_mul m2(.clock(clk), .reset(reset), .start(start_d), .mlier(b_reg), .mcand(g_reg), .valid(v2), .prodt_end(q_raw));

  sequ_mul m3(.clock(clk), .reset(reset), .start(start_d), .mlier(a_reg), .mcand(f_reg), .valid(v3), .prodt_end(r_raw));
  sequ_mul m4(.clock(clk), .reset(reset), .start(start_d), .mlier(b_reg), .mcand(h_reg), .valid(v4), .prodt_end(s_raw));

  sequ_mul m5(.clock(clk), .reset(reset), .start(start_d), .mlier(c_reg), .mcand(e_reg), .valid(v5), .prodt_end(t_raw));
  sequ_mul m6(.clock(clk), .reset(reset), .start(start_d), .mlier(d_reg), .mcand(g_reg), .valid(v6), .prodt_end(u_raw));

  sequ_mul m7(.clock(clk), .reset(reset), .start(start_d), .mlier(c_reg), .mcand(f_reg), .valid(v7), .prodt_end(v_raw));
  sequ_mul m8(.clock(clk), .reset(reset), .start(start_d), .mlier(d_reg), .mcand(h_reg), .valid(v8), .prodt_end(k_raw));

endmodule


// ==========================================================
// 子模組: sequ_mul (序列式移位加法乘法器)
// Note: Modified to support signed numbers (Magnitude-Sign approach)
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
  localparam SIGN = 2'b11; // New state for sign correction
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

  // 組合邏輯
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
        if (count == 1) next_state = SIGN; // Go to SIGN state first
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
           // Apply sign correction if needed
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
