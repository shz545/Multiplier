##----------------------------------------##
##   Power Analysis Script (Post-Sim)     ##
##----------------------------------------##

#####################################
#  1. 環境與參數設定                #
#####################################

# 設定與 Synthesis.tcl 相同的 Library 路徑
set search_path "/usr/Library/CBDK_TSMC018_Arm_f1.0/CIC/SynopsysDC/db /usr/cad/synopsys/synthesis/2022.03/libraries/syn"
set target_library "slow.db"
set link_library   "slow.db"
set symbol_library "slow.db"

# 設定設計名稱與檔案名稱
set design_name "matrix_multiplier"
set netlist_file "./netlist/${design_name}_syn.v"
set sdc_file     "./netlist/${design_name}_postdc.sdc"
set saif_file    "[pwd]/matrix_multiplier.saif"

# ★★★ 關鍵設定：SAIF 中的路徑 ★★★
# 這裡必須對應您 Testbench 中的實例路徑 (tb_module_name/instance_name)
set saif_instance "tb_matrix_multiplier/u_dut"


#####################################
#  2. 讀取設計 (Read Netlist)       #
#####################################

# 清除舊的設計
remove_design -all

# 讀取合成後的 Netlist
read_verilog $netlist_file

# 設定頂層模組
current_design $design_name

# 連結 Library (這步很重要，會檢查邏輯閘是否都找得到)
link


#####################################
#  3. 恢復時序環境 (Read SDC)       #
#####################################

# 讀取合成時產生的 SDC 檔，讓 DC 知道時脈頻率 (10ns)
# 這樣計算 P = CV^2f 時，頻率 f 才是對的
if {[file exists $sdc_file]} {
    read_sdc $sdc_file
} else {
    puts "Warning: SDC file not found! Power analysis might be inaccurate."
    # 如果找不到 SDC，至少手動建一個 clock (保險起見)
    create_clock -name clk -period 10.0 [get_ports clk]
}


#####################################
#  4. 讀取 SAIF (Read Activity)     #
#####################################

# 檢查 SAIF 檔案是否存在
if {[file exists $saif_file]} {
    puts "Reading SAIF file: $saif_file ..."
    
    # 讀取 SAIF
    # -input: 模擬產生的檔案
    # -instance: Testbench 中指向 DUT 的路徑
    read_saif -input $saif_file -instance $saif_instance -verbose
    
} else {
    puts "Error: SAIF file '$saif_file' not found!"
    quit
}


#####################################
#  5. 產生功耗報告 (Report Power)   #
#####################################

# 檢查完整性報告 (看有多少訊號成功對應到 SAIF)
# 如果 annotating rate 太低 (例如 < 10%)，代表路徑設錯了
report_saif -hier > ./Synthesis/saif_annotation.rpt

# 1. 總功耗報告
report_power > ./Synthesis/power_post_sim.rpt

# 2. 分層功耗報告 (可以看到各個模組的耗電)
report_power -hierarchy > ./Synthesis/power_hierarchy.rpt

# 3. 詳細功耗報告 (包含 Net 切換率)
report_power -verbose > ./Synthesis/power_verbose.rpt


puts "------------------------------------------------"
puts " Power Analysis Completed."
puts " Reports are saved in ./Synthesis/ directory."
puts "------------------------------------------------"

# 結束
quit
