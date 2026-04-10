`timescale 1ns / 1ps

module riscv_processor(
    input             clk,
    output reg [31:0] mem_addr,    // address bus
    output reg [31:0] mem_wdata,   // data to be written
    output reg [3 :0] mem_wmask,   // write mask for the 4 bytes of each word
    input      [31:0] mem_rdata,   // input lines for both data and instr
    output reg        mem_rstrb,   // active to initiate memory read (used by IO)
    input             mem_rbusy,   // asserted if memory is busy reading value
    input             mem_wbusy,   // asserted if memory is busy writing value
    input             reset        // set to 0 to reset the processor
);

    // ==========================================
    // Internal Registers and State Declarations
    // ==========================================
    reg [31:0] x [0:31];       // 32 General Purpose Registers
    reg [31:0] pc;             // Program Counter
    reg [31:0] instr;          // Instruction Register
    reg [31:0] load_store_addr;// Holds memory address during wait states

    // FSM States
    localparam STATE_RESET      = 3'd0;
    localparam STATE_FETCH_REQ  = 3'd1;
    localparam STATE_FETCH_WAIT = 3'd2;
    localparam STATE_EXECUTE    = 3'd3;
    localparam STATE_MEM_R_WAIT = 3'd4;
    localparam STATE_MEM_W_WAIT = 3'd5;

    reg [2:0] state;

    // ==========================================
    //          Instruction Decoding Wires
    // ==========================================
    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];
    wire [4:0] rd     = instr[11:7];
    wire [4:0] rs1    = instr[19:15];
    wire [4:0] rs2    = instr[24:20];

    // Immediate generation mappings
    wire [31:0] imm_i = { {20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = { {20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = { {20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = { {12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

    // Register file read
    wire [31:0] rdata1 = (rs1 == 5'b0) ? 32'b0 : x[rs1];
    wire [31:0] rdata2 = (rs2 == 5'b0) ? 32'b0 : x[rs2];

    // Signed versions for proper Arithmetic comparisons/shifts
    wire signed [31:0] signed_rdata1 = rdata1;
    wire signed [31:0] signed_rdata2 = rdata2;
    wire signed [31:0] signed_imm_i  = imm_i;

    // ==========================================
    //                  Opcodes
    // ==========================================
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_IMM    = 7'b0010011;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_REG    = 7'b0110011;
    localparam OP_LUI    = 7'b0110111;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_JAL    = 7'b1101111;

    // ==========================================
    //      Combinatorial Logic: Branch & ALU
    // ==========================================
    reg take_branch;
    always @(*) begin
        case(funct3)
            3'b000: take_branch = (rdata1 == rdata2);                           // BEQ
            3'b001: take_branch = (rdata1 != rdata2);                           // BNE
            3'b100: take_branch = (signed_rdata1 < signed_rdata2);              // BLT (Signed)
            3'b101: take_branch = (signed_rdata1 >= signed_rdata2);             // BGE (Signed)
            3'b110: take_branch = (rdata1 < rdata2);                            // BLTU
            3'b111: take_branch = (rdata1 >= rdata2);                           // BGEU
            default:take_branch = 1'b0;
        endcase
    end

    reg [31:0] alu_out;
    always @(*) begin
        if(opcode == OP_REG) begin
            case(funct3)
                3'b000: alu_out = (funct7 == 7'h20) ? (rdata1 - rdata2) : (rdata1 + rdata2); 
                3'b001: alu_out = rdata1 << rdata2[4:0];
                3'b010: alu_out = (signed_rdata1 < signed_rdata2) ? 32'd1 : 32'd0;       
                3'b011: alu_out = (rdata1 < rdata2) ? 32'd1 : 32'd0;                         
                3'b100: alu_out = rdata1 ^ rdata2;                                           
                3'b101: begin
                    if(funct7 == 7'h20) alu_out = $signed(rdata1) >>> rdata2[4:0];  // SRA
                    else alu_out = rdata1 >> rdata2[4:0];                           // SRL
                end
                3'b110: alu_out = rdata1 | rdata2;                                           
                3'b111: alu_out = rdata1 & rdata2;                                           
            endcase
        end
        else if(opcode == OP_IMM) begin
            case(funct3)
                3'b000: alu_out = rdata1 + imm_i;                                            
                3'b001: alu_out = rdata1 << imm_i[4:0];                                      
                3'b010: alu_out = (signed_rdata1 < signed_imm_i) ? 32'd1 : 32'd0;        
                3'b011: alu_out = (rdata1 < imm_i) ? 32'd1 : 32'd0;                          
                3'b100: alu_out = rdata1 ^ imm_i;                                            
                3'b101: begin
                    if(funct7 == 7'h20) alu_out = $signed(rdata1) >>> imm_i[4:0];   // SRAI
                    else alu_out = rdata1 >> imm_i[4:0];                            // SRLI
                end
                3'b110: alu_out = rdata1 | imm_i;                                            
                3'b111: alu_out = rdata1 & imm_i;                                            
            endcase
        end
        else alu_out = 32'b0;
    end

    // Combinatorial Logic for formatting Load Data
    reg [31:0] load_data;
    wire [1:0] byte_offset = load_store_addr[1:0];
    always @(*) begin
        case(funct3)
            3'b000: begin // LB (Load Byte - Sign Extended)
                case(byte_offset)
                    2'b00: load_data = {{24{mem_rdata[ 7]}}, mem_rdata[7:0]};
                    2'b01: load_data = {{24{mem_rdata[15]}}, mem_rdata[15:8]};
                    2'b10: load_data = {{24{mem_rdata[23]}}, mem_rdata[23:16]};
                    2'b11: load_data = {{24{mem_rdata[31]}}, mem_rdata[31:24]};
                endcase
            end
            3'b001: begin // LH (Load Halfword - Sign Extended)
                case(byte_offset[1])
                    1'b0: load_data = {{16{mem_rdata[15]}}, mem_rdata[15:0 ]};
                    1'b1: load_data = {{16{mem_rdata[31]}}, mem_rdata[31:16]};
                endcase
            end
            3'b010: load_data = mem_rdata; // LW (Load Word)
            3'b100: begin // LBU (Load Byte Unsigned - Zero Extended)
                case(byte_offset)
                    2'b00: load_data = {24'b0, mem_rdata[ 7:0 ]};
                    2'b01: load_data = {24'b0, mem_rdata[15: 8]};
                    2'b10: load_data = {24'b0, mem_rdata[23:16]};
                    2'b11: load_data = {24'b0, mem_rdata[31:24]};
                endcase
            end
            3'b101: begin // LHU (Load Halfword Unsigned - Zero Extended)
                case(byte_offset[1])
                    1'b0: load_data = {16'b0, mem_rdata[15:0 ]};
                    1'b1: load_data = {16'b0, mem_rdata[31:16]};
                endcase
            end
            default: load_data = 32'b0;
        endcase
    end

    // ==========================================
    //      Synchronous FSM & Processor Core
    // ==========================================
    integer i;

    always @(posedge clk) begin
        if(reset) begin
            state <= STATE_FETCH_REQ;
            pc <= 32'b0;
            mem_addr <= 32'b0;
            mem_wdata <= 32'b0;
            mem_wmask <= 4'b0;
            mem_rstrb <= 1'b0;
            load_store_addr <= 32'b0;
            for(i=0; i<32; i=i+1) begin
                x[i] <= 32'b0;
            end
        end
        else begin
            case(state)
                STATE_FETCH_REQ: begin
                    mem_addr <= pc;
                    mem_rstrb <= 1'b1;
                    mem_wmask <= 4'b0;
                    state <= STATE_FETCH_WAIT;
                end

                STATE_FETCH_WAIT: begin
                    if(!mem_rbusy) begin
                        instr <= mem_rdata;
                        mem_rstrb <= 1'b0;
                        state <= STATE_EXECUTE;
                    end
                end

                STATE_EXECUTE: begin
                    case(opcode)
                        OP_LUI: begin
                            if(rd != 5'b0) x[rd] <= imm_u;
                            pc <= pc + 4;
                            state <= STATE_FETCH_REQ;
                        end

                        OP_AUIPC: begin
                            if(rd != 5'b0) x[rd] <= pc + imm_u;
                            pc <= pc + 4;
                            state <= STATE_FETCH_REQ;
                        end

                        OP_JAL: begin
                            if(rd != 5'b0) x[rd] <= pc + 4;
                            pc <= pc + imm_j;
                            state <= STATE_FETCH_REQ;
                        end

                        OP_JALR: begin
                            if(rd != 5'b0) x[rd] <= pc + 4;
                            pc <= (rdata1 + imm_i) & ~32'h1; 
                            state <= STATE_FETCH_REQ;
                        end

                        OP_BRANCH: begin
                            if(take_branch) pc <= pc + imm_b;
                            else pc <= pc + 4;
                            state <= STATE_FETCH_REQ;
                        end

                        OP_REG, OP_IMM: begin
                            if(rd != 5'b0) x[rd] <= alu_out;
                            pc <= pc + 4;
                            state <= STATE_FETCH_REQ;
                        end

                        OP_LOAD: begin
                            load_store_addr <= rdata1 + imm_i;
                            mem_addr <= (rdata1 + imm_i) & 32'hFFFFFFFC; 
                            mem_rstrb <= 1'b1;
                            state <= STATE_MEM_R_WAIT;
                        end

                        OP_STORE: begin
                            load_store_addr <= rdata1 + imm_s;
                            mem_addr <= (rdata1 + imm_s) & 32'hFFFFFFFC; 
                            
                            case(funct3)
                                3'b000: begin 
                                    mem_wmask <= 4'b0001 << ((rdata1 + imm_s) & 2'b11);
                                    mem_wdata <= rdata2 << (8 * ((rdata1 + imm_s) & 2'b11));
                                end
                                3'b001: begin 
                                    mem_wmask <= 4'b0011 << ((rdata1 + imm_s) & 2'b11);
                                    mem_wdata <= rdata2 << (8 * ((rdata1 + imm_s) & 2'b11));
                                end
                                3'b010: begin 
                                    mem_wmask <= 4'b1111;
                                    mem_wdata <= rdata2;
                                end
                                default: mem_wmask <= 4'b0000;
                            endcase
                            state <= STATE_MEM_W_WAIT;
                        end

                        default: begin
                            pc <= pc + 4;
                            state <= STATE_FETCH_REQ;
                        end
                    endcase
                end

                STATE_MEM_R_WAIT: begin
                    if(!mem_rbusy) begin
                        if(rd != 5'b0) x[rd] <= load_data;
                        pc <= pc + 4;
                        mem_rstrb <= 1'b0;
                        state <= STATE_FETCH_REQ;
                    end
                end

                STATE_MEM_W_WAIT: begin
                    if(!mem_wbusy) begin
                        pc <= pc + 4;
                        mem_wmask <= 4'b0;
                        state <= STATE_FETCH_REQ;
                    end
                end
            endcase
        end
    end

endmodule