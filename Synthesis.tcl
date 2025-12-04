##----------------------------------------##
##   NCYU DIC Class : Synthesis Script    ##
##   (Revised Version)                    ##
##----------------------------------------##


#####################################
#  1. Library and Design Setup      #
#####################################

# 設定搜尋函式庫的路徑
# !! 請確認此路徑在您的環境中是正確的 !!
set search_path "/usr/Library/CBDK_TSMC018_Arm_f1.0/CIC/SynopsysDC/db /usr/cad/synopsys/synthesis/2022.03/libraries/syn"

# 設定目標製程庫
set target_library "slow.db"
set link_library   "slow.db"
set symbol_library "slow.db"

# 設定頂層模組的名稱
set design_name "matrix_multiplier"


#####################################
#  2. Read Verilog Code             #
#####################################

# 使用 analyze 和 elaborate 來讀取多個 Verilog 檔案，避免連結錯誤
# 請確認檔案路徑正確
analyze -format verilog { \
    ./RTL/register_rom.v \
    ./RTL/simple_dual_port_ram.v \
    ./RTL/booth_fsm.v \
    ./RTL/matrix_multiplier.v \
}
elaborate $design_name


#####################################
#  3. Set Current Design            #
#####################################

# 將當前操作的設計設為頂層模組
current_design $design_name
link
uniquify


#####################################
#  4. Timing Constraints            #
#####################################

# 設定時脈週期為 10ns (100MHz)
set CLK_PERIOD 10.0

# 建立時脈約束，這是最重要的時序指令
create_clock -name clk -period $CLK_PERIOD  [get_ports clk] 

# 設定時脈的不確定性 (jitter, skew)，通常設為週期的 5%-10%
set_clock_uncertainty [expr $CLK_PERIOD * 0.1] [get_clocks *]

# 設定輸入輸出的延遲，告知合成工具外部電路的時序特性
# 假設外部訊號在時脈觸發後 2ns 內穩定
set_input_delay  [expr $CLK_PERIOD * 0.2] -clock [get_clocks *] [all_inputs]
# 假設輸出訊號需要給外部電路 2ns 的時間來接收
set_output_delay [expr $CLK_PERIOD * 0.2] -clock [get_clocks *] [all_outputs]

# set_max_delay 不適用於有時脈的同步電路，因此註解掉
# set_max_delay 10 -from [all_inputs] -to [all_outputs]


#####################################
#  5. Pre-Compile Checks            #
#####################################

# 執行前先檢查設計，並將報告輸出到 Synthesis 目錄
check_design > ./Synthesis/check_design_before_compile.report
check_timing > ./Synthesis/check_timing_before_compile.report


#####################################
#  6. Compile (Synthesize)          #
#####################################

# 讓合成工具自動處理層次結構
set_flatten true

# 執行合成，使用較高的努力程度以獲得更好的結果
compile -map_effort high


#####################################
#  7. Write Output Files            #
#####################################

# 將合成後的網表、時序資訊(SDF)和約束(SDC)寫入 Netlist 目錄
write_sdf -version 2.1 ./netlist/${design_name}_postdc.sdf
write -format verilog -hierarchy -output ./netlist/${design_name}_syn.v
write_sdc ./netlist/${design_name}_postdc.sdc


#####################################
#  8. Generate Reports              #
#####################################

# 產生面積、時序和功耗報告，並存於 Synthesis 目錄
report_area > ./Synthesis/area.rpt
report_timing > ./Synthesis/timing.rpt
report_power > ./Synthesis/power_pre_sim.rpt


#####################################
#  9. Post-Simulation Power Analysis (Optional) #
#####################################
# 1. 讀取設計 (如果已經關掉 dc_shell，需要重新讀入 netlist)
# 如果您 dc_shell 還開著，這步不用做。
# 如果重開了，請先執行:
# read_verilog ./netlist/matrix_multiplier_syn.v
# current_design matrix_multiplier
# link

# 2. 讀取 SAIF 檔案 (關鍵!)
# -input: 剛剛 VCS 產生的檔案
# -instance: Testbench 裡面的 DUT 實例路徑 (tb_matrix_multiplier/u_dut)
#read_saif -input matrix_multiplier.saif -instance tb_matrix_multiplier/u_dut

# 3. 產生報告
# 這次算出來的數字，就是包含真實翻轉率的精確功耗！
#report_power > ./Synthesis/power_post_sim.rpt

# (選用) 也可以看看分層報告，看哪個模組最耗電
#report_power -hierarchy > ./Synthesis/power_hierarchy.rpt
#####################################


#####################################
#  10. Post-Compile Checks          #
#####################################

check_design > ./Synthesis/check_design_post_compile.report
check_timing > ./Synthesis/check_timing_post_compile.report


#####################################
#  11. GUI and Exit                 #
#####################################

# 如果需要在合成後開啟圖形介面進行分析，請取消下一行的註解
 gui_start

# 結束腳本執行
quit
