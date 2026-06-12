// cache_controller.v
// FSM controller for a 4-way set-associative write-back / write-allocate cache.
// States: IDLE → READ_HIT | WRITE_HIT | EVICT → READ_MISS | WRITE_MISS → IDLE

`timescale 1ns/1ps

module cache_controller #(
    parameter NUM_SETS   = 128,
    parameter NUM_WAYS   = 4,
    parameter TAG_W      = 18,
    parameter BLOCK_BITS = 512
)(
    input  wire clk,
    input  wire rst,

    // CPU interface
    input  wire        cpu_req,
    input  wire        cpu_rw,        // 0=read, 1=write
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    output reg  [31:0] cpu_rdata,
    output reg         cpu_ready,

    // Main memory interface
    input  wire         mem_ready,
    input  wire [511:0] mem_rdata,
    output reg          mem_req,
    output reg          mem_rw,       // 0=fetch, 1=writeback
    output reg  [31:0]  mem_addr,
    output reg  [511:0] mem_wdata,

    // Per-way data from cache_memory (all 4 ways, combinational)
    input  wire        cm_valid0, cm_dirty0,
    input  wire [TAG_W-1:0]      cm_tag0,
    input  wire [BLOCK_BITS-1:0] cm_data0,

    input  wire        cm_valid1, cm_dirty1,
    input  wire [TAG_W-1:0]      cm_tag1,
    input  wire [BLOCK_BITS-1:0] cm_data1,

    input  wire        cm_valid2, cm_dirty2,
    input  wire [TAG_W-1:0]      cm_tag2,
    input  wire [BLOCK_BITS-1:0] cm_data2,

    input  wire        cm_valid3, cm_dirty3,
    input  wire [TAG_W-1:0]      cm_tag3,
    input  wire [BLOCK_BITS-1:0] cm_data3,

    output wire [6:0]  cm_r_set,

    // Full-line write port to cache_memory
    output reg         cm_w_en,
    output reg  [6:0]  cm_w_set,
    output reg  [1:0]  cm_w_way,
    output reg         cm_w_valid,
    output reg         cm_w_dirty,
    output reg  [TAG_W-1:0]      cm_w_tag,
    output reg  [BLOCK_BITS-1:0] cm_w_data,

    // Single-word write port to cache_memory
    output reg         cm_ww_en,
    output reg  [6:0]  cm_ww_set,
    output reg  [1:0]  cm_ww_way,
    output reg  [4:0]  cm_ww_offset,
    output reg  [31:0] cm_ww_word,

    // LRU controller ports
    output reg         lru_access_valid,
    output reg  [6:0]  lru_access_set,
    output reg  [1:0]  lru_access_way,
    output wire [6:0]  lru_query_set,
    input  wire [1:0]  lru_way
);

    localparam IDLE       = 3'd0;
    localparam READ_HIT   = 3'd1;
    localparam READ_MISS  = 3'd2;
    localparam WRITE_HIT  = 3'd3;
    localparam WRITE_MISS = 3'd4;
    localparam EVICT      = 3'd5;

    reg [2:0] state, next_state;

    // Latched request fields (captured on arrival in IDLE)
    reg [TAG_W-1:0] req_tag;
    reg [6:0]       req_set;
    reg [4:0]       req_offset;
    reg [31:0]      req_wdata;
    reg             req_rw;

    wire [TAG_W-1:0] dec_tag    = cpu_addr[31:14];
    wire [6:0]       dec_set    = cpu_addr[13:7];
    wire [4:0]       dec_offset = cpu_addr[6:2];

    // Use incoming address in IDLE, latched address in all other states
    assign cm_r_set      = (state == IDLE) ? dec_set : req_set;
    assign lru_query_set = (state == IDLE) ? dec_set : req_set;

    // In IDLE we must compare against the *current* incoming tag, not the latched one.
    // req_tag still holds the previous request's value until the end of this cycle.
    wire [TAG_W-1:0] cmp_tag = (state == IDLE) ? dec_tag : req_tag;

    reg        is_hit;
    reg  [1:0] hit_way;
    reg  [1:0] hit_way_r;   // registered copy, valid during HIT states

    always @(*) begin
        is_hit  = 1'b0;
        hit_way = 2'd0;
        if (cm_valid0 && cm_tag0 == cmp_tag) begin is_hit = 1'b1; hit_way = 2'd0; end
        if (cm_valid1 && cm_tag1 == cmp_tag) begin is_hit = 1'b1; hit_way = 2'd1; end
        if (cm_valid2 && cm_tag2 == cmp_tag) begin is_hit = 1'b1; hit_way = 2'd2; end
        if (cm_valid3 && cm_tag3 == cmp_tag) begin is_hit = 1'b1; hit_way = 2'd3; end
    end

    wire [1:0] evict_way = lru_way;

    reg evict_dirty;
    always @(*) begin
        case (evict_way)
            2'd0: evict_dirty = cm_dirty0;
            2'd1: evict_dirty = cm_dirty1;
            2'd2: evict_dirty = cm_dirty2;
            default: evict_dirty = cm_dirty3;
        endcase
    end

    reg [BLOCK_BITS-1:0] evict_data;
    reg [TAG_W-1:0]      evict_tag;
    always @(*) begin
        case (evict_way)
            2'd0: begin evict_data = cm_data0; evict_tag = cm_tag0; end
            2'd1: begin evict_data = cm_data1; evict_tag = cm_tag1; end
            2'd2: begin evict_data = cm_data2; evict_tag = cm_tag2; end
            default: begin evict_data = cm_data3; evict_tag = cm_tag3; end
        endcase
    end

    reg [BLOCK_BITS-1:0] hit_data;
    always @(*) begin
        case (hit_way_r)
            2'd0: hit_data = cm_data0;
            2'd1: hit_data = cm_data1;
            2'd2: hit_data = cm_data2;
            default: hit_data = cm_data3;
        endcase
    end

    // Sequential: register state, latch request on new arrival
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= IDLE;
            req_tag    <= {TAG_W{1'b0}};
            req_set    <= 7'd0;
            req_offset <= 5'd0;
            req_wdata  <= 32'd0;
            req_rw     <= 1'b0;
            hit_way_r  <= 2'd0;
        end else begin
            state <= next_state;
            if (state == IDLE && cpu_req) begin
                req_tag    <= dec_tag;
                req_set    <= dec_set;
                req_offset <= dec_offset;
                req_wdata  <= cpu_wdata;
                req_rw     <= cpu_rw;
                hit_way_r  <= hit_way;
            end
        end
    end

    // Combinational: next state and all output signals
    always @(*) begin
        // safe defaults
        next_state       = state;
        cpu_rdata        = 32'd0;
        cpu_ready        = 1'b0;
        mem_req          = 1'b0;
        mem_rw           = 1'b0;
        mem_addr         = 32'd0;
        mem_wdata        = {BLOCK_BITS{1'b0}};
        cm_w_en          = 1'b0;
        cm_w_set         = 7'd0;
        cm_w_way         = 2'd0;
        cm_w_valid       = 1'b0;
        cm_w_dirty       = 1'b0;
        cm_w_tag         = {TAG_W{1'b0}};
        cm_w_data        = {BLOCK_BITS{1'b0}};
        cm_ww_en         = 1'b0;
        cm_ww_set        = 7'd0;
        cm_ww_way        = 2'd0;
        cm_ww_offset     = 5'd0;
        cm_ww_word       = 32'd0;
        lru_access_valid = 1'b0;
        lru_access_set   = req_set;
        lru_access_way   = 2'd0;

        case (state)

            IDLE: begin
                if (cpu_req) begin
                    if      (!cpu_rw && is_hit)        next_state = READ_HIT;
                    else if ( cpu_rw && is_hit)        next_state = WRITE_HIT;
                    else if (!is_hit && evict_dirty)   next_state = EVICT;
                    else if (!cpu_rw)                  next_state = READ_MISS;
                    else                               next_state = WRITE_MISS;
                end
            end

            READ_HIT: begin
                cpu_rdata        = hit_data[req_offset*32 +: 32];
                cpu_ready        = 1'b1;
                lru_access_valid = 1'b1;
                lru_access_set   = req_set;
                lru_access_way   = hit_way_r;
                next_state       = IDLE;
            end

            WRITE_HIT: begin
                cm_ww_en         = 1'b1;
                cm_ww_set        = req_set;
                cm_ww_way        = hit_way_r;
                cm_ww_offset     = req_offset;
                cm_ww_word       = req_wdata;
                cpu_ready        = 1'b1;
                lru_access_valid = 1'b1;
                lru_access_set   = req_set;
                lru_access_way   = hit_way_r;
                next_state       = IDLE;
            end

            // Dirty LRU line: write back to memory before filling.
            // Eviction address is reconstructed from stored tag + current set.
            EVICT: begin
                mem_req   = 1'b1;
                mem_rw    = 1'b1;
                mem_addr  = {evict_tag, req_set, 7'd0};
                mem_wdata = evict_data;
                if (mem_ready)
                    next_state = req_rw ? WRITE_MISS : READ_MISS;
            end

            READ_MISS: begin
                mem_req  = 1'b1;
                mem_rw   = 1'b0;
                mem_addr = {req_tag, req_set, 7'd0};
                if (mem_ready) begin
                    cm_w_en    = 1'b1;
                    cm_w_set   = req_set;
                    cm_w_way   = evict_way;
                    cm_w_valid = 1'b1;
                    cm_w_dirty = 1'b0;
                    cm_w_tag   = req_tag;
                    cm_w_data  = mem_rdata;
                    cpu_rdata        = mem_rdata[req_offset*32 +: 32];
                    cpu_ready        = 1'b1;
                    lru_access_valid = 1'b1;
                    lru_access_set   = req_set;
                    lru_access_way   = evict_way;
                    next_state       = IDLE;
                end
            end

            // Write-allocate: fetch block first, merge CPU write word, install dirty.
            WRITE_MISS: begin
                mem_req  = 1'b1;
                mem_rw   = 1'b0;
                mem_addr = {req_tag, req_set, 7'd0};
                if (mem_ready) begin
                    cm_w_en    = 1'b1;
                    cm_w_set   = req_set;
                    cm_w_way   = evict_way;
                    cm_w_valid = 1'b1;
                    cm_w_dirty = 1'b1;
                    cm_w_tag   = req_tag;
                    cm_w_data                      = mem_rdata;
                    cm_w_data[req_offset*32 +: 32] = req_wdata;
                    cpu_ready        = 1'b1;
                    lru_access_valid = 1'b1;
                    lru_access_set   = req_set;
                    lru_access_way   = evict_way;
                    next_state       = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

endmodule
