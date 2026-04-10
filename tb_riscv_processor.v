`timescale 1ns / 1ps

module tb_riscv_processor;

    // DUT Signals
    reg clk;
    reg reset;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [ 3:0] mem_wmask;
    reg  [31:0] mem_rdata;
    wire        mem_rstrb;
    wire        mem_rbusy;
    wire        mem_wbusy;

    // Memory Model Array 
    reg [7:0] memory [0:2047];

    // Instantiate Processor
    riscv_processor dut (
        .clk(clk),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wmask(mem_wmask),
        .mem_rdata(mem_rdata),
        .mem_rstrb(mem_rstrb),
        .mem_rbusy(mem_rbusy),
        .mem_wbusy(mem_wbusy),
        .reset(reset)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Memory Bus Simulator (Robust combinational handshaking)
    reg [1:0] delay_cnt_r;
    reg [1:0] delay_cnt_w;

    // Combinational busy flags ensure processor FSM doesn't skip a beat
    assign mem_rbusy = (mem_rstrb && delay_cnt_r < 1);
    assign mem_wbusy = ((mem_wmask != 0) && delay_cnt_w < 1);

    always @(posedge clk) begin
        if(reset) begin
            delay_cnt_r <= 0;
            delay_cnt_w <= 0;
        end
        else begin
            // Read logic
            if(mem_rstrb) begin
                if(delay_cnt_r == 0) begin
                    mem_rdata <= {memory[mem_addr+3], memory[mem_addr+2], memory[mem_addr+1], memory[mem_addr]};
                    delay_cnt_r <= 1;
                end
            end
            else delay_cnt_r <= 0;

            // Write logic
            if(mem_wmask != 0) begin
                if(delay_cnt_w == 0) begin
                    if(mem_wmask[0]) memory[mem_addr]   <= mem_wdata[ 7: 0];
                    if(mem_wmask[1]) memory[mem_addr+1] <= mem_wdata[15: 8];
                    if(mem_wmask[2]) memory[mem_addr+2] <= mem_wdata[23:16];
                    if(mem_wmask[3]) memory[mem_addr+3] <= mem_wdata[31:24];
                    delay_cnt_w <= 1;
                end
            end
            else delay_cnt_w <= 0;
        end
    end

    // Instruction Writing Tasks (A mini assembler)
    task write_inst;
        input [31:0] addr;
        input [31:0] inst;
        begin
            memory[addr]   = inst[7:0];
            memory[addr+1] = inst[15:8];
            memory[addr+2] = inst[23:16];
            memory[addr+3] = inst[31:24];
        end
    endtask

    // Opcode mapping functions
    function [31:0] R_type(input [6:0] op, input [2:0] f3, input [6:0] f7, input [4:0] rd, input [4:0] r1, input [4:0] r2);
        R_type = {f7, r2, r1, f3, rd, op};
    endfunction

    function [31:0] I_type(input [6:0] op, input [2:0] f3, input [4:0] rd, input [4:0] r1, input [11:0] imm);
        I_type = {imm, r1, f3, rd, op};
    endfunction

    function [31:0] S_type(input [6:0] op, input [2:0] f3, input [4:0] r1, input [4:0] r2, input [11:0] imm);
        S_type = {imm[11:5], r2, r1, f3, imm[4:0], op};
    endfunction

    function [31:0] B_type(input [6:0] op, input [2:0] f3, input [4:0] r1, input [4:0] r2, input [13:0] imm);
        B_type = {imm[12], imm[10:5], r2, r1, f3, imm[4:1], imm[11], op};
    endfunction

    function [31:0] U_type(input [6:0] op, input [4:0] rd, input [31:12] imm);
        U_type = {imm, rd, op};
    endfunction
    
    function [31:0] J_type(input [6:0] op, input [4:0] rd, input [20:0] imm);
        J_type = {imm[20], imm[10:1], imm[11], imm[19:12], rd, op};
    endfunction

    // Base Opcodes
    localparam OP_R = 7'b0110011, OP_I = 7'b0010011, OP_L = 7'b0000011, OP_S = 7'b0100011;
    localparam OP_B = 7'b1100011, OP_J = 7'b1101111, OP_JR= 7'b1100111, OP_U = 7'b0110111;

    integer i;
    
    initial begin
        // Zero out memory
        for(i=0; i<2048; i=i+1) memory[i] = 8'b0;

        // --- Load Machine Code ---
        // 0: ADDI x1, x0, 10
        write_inst(0,  I_type(OP_I, 3'b000, 1, 0, 12'd10));
        // 4: ADDI x2, x0, -5 -> 111111111011
        write_inst(4,  I_type(OP_I, 3'b000, 2, 0, 12'hFFB));
        // 8: ADD x3, x1, x2 -> x3 = 5
        write_inst(8,  R_type(OP_R, 3'b000, 7'h00, 3, 1, 2));
        // 12: SUB x4, x1, x2 -> x4 = 15
        write_inst(12, R_type(OP_R, 3'b000, 7'h20, 4, 1, 2));
        // 16: SLT x5, x2, x1 -> x5 = 1 (-5 < 10)
        write_inst(16, R_type(OP_R, 3'b010, 7'h00, 5, 2, 1));
        // 20: SLTU x6, x2, x1 -> x6 = 0 (Unsigned -5 is > 10)
        write_inst(20, R_type(OP_R, 3'b011, 7'h00, 6, 2, 1));
        // 24: ADDI x8, x0, 2
        write_inst(24, I_type(OP_I, 3'b000, 8, 0, 12'd2));
        // 28: SLL x7, x1, x8 -> x7 = 40 (10 << 2)
        write_inst(28, R_type(OP_R, 3'b001, 7'h00, 7, 1, 8));
        // 32: SRA x9, x2, x8 -> x9 = -2 (-5 >> 2)
        write_inst(32, R_type(OP_R, 3'b101, 7'h20, 9, 2, 8));
        // 36: LUI x10, 0x12345 -> x10 = 0x12345000
        write_inst(36, U_type(OP_U, 10, 20'h12345));
        // 40: SW x4, 100(x0) -> mem[100] = 15
        write_inst(40, S_type(OP_S, 3'b010, 0, 4, 12'd100));
        // 44: LW x11, 100(x0) -> x11 = 15
        write_inst(44, I_type(OP_L, 3'b010, 11, 0, 12'd100));
        // 48: BEQ x4, x11, 8 -> Branch forward 8 bytes (to PC=56)
        write_inst(48, B_type(OP_B, 3'b000, 4, 11, 14'd8));
        // 52: ADDI x12, x0, 999 -> Skipped! 
        write_inst(52, I_type(OP_I, 3'b000, 12, 0, 12'd999));
        // 56: JAL x13, 8 -> PC becomes 64, x13 = 60
        write_inst(56, J_type(OP_J, 13, 21'd8));
        // 60: ADDI x12, x0, 999 -> Skipped!
        write_inst(60, I_type(OP_I, 3'b000, 12, 0, 12'd999));
        // 64: BNE x0, x0, 0 (Infinite loop stopper)
        write_inst(64, B_type(OP_B, 3'b001, 0, 0, 14'd0));

        // Init System
        reset = 1;
        #20;
        reset = 0;

        #2000; 
        
        $display("Execution Completed. Checking Register States:\n");
        $display("x1  (ADDI) = %d [Expected: 10]", dut.x[1]);
        $display("x2  (ADDI) = %d [Expected: -5]", $signed(dut.x[2]));
        $display("x3  (ADD)  = %d [Expected: 5]", dut.x[3]);
        $display("x4  (SUB)  = %d [Expected: 15]", dut.x[4]);
        $display("x5  (SLT)  = %d [Expected: 1]", dut.x[5]);
        $display("x6  (SLTU) = %d [Expected: 0]", dut.x[6]);
        $display("x7  (SLL)  = %d [Expected: 40]", dut.x[7]);
        $display("x9  (SRA)  = %d [Expected: -2]", $signed(dut.x[9]));
        $display("x10 (LUI)  = %h [Expected: 12345000]", dut.x[10]);
        $display("x11 (LW)   = %d [Expected: 15]", dut.x[11]);
        $display("x12 (SKIP) = %d [Expected: 0]", dut.x[12]);
        $display("x13 (JAL)  = %d [Expected: 60]", dut.x[13]);
        
        $display("\n====================================================");
        if(dut.x[1] == 10 && $signed(dut.x[2]) == -5 && dut.x[3] == 5 && dut.x[4] == 15 && dut.x[5] == 1 && dut.x[6] == 0 && dut.x[7] == 40 && $signed(dut.x[9]) == -2 && dut.x[10] == 32'h12345000 && dut.x[11] == 15 && dut.x[12] == 0 && dut.x[13] == 60) begin
            $display("ALL TESTS PASSED");
        end
        else begin
            $display("FAILED");
        end
        $display("====================================================\n");
        
        $finish;
    end
endmodule