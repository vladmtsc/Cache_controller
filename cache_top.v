// cache_top.v
// Top-level module: wires together address_decoder, lru_controller,
// cache_memory, and cache_controller.

`timescale 1ns/1ps

module cache_top #(
    parameter NUM_SETS   = 128,
    parameter NUM_WAYS   = 4,
    parameter TAG_W      = 18,
    parameter BLOCK_BITS = 512
)(
    input  wire        clk,
    input  wire        rst,

    // ---- CPU interface ----
    input  wire        cpu_req,
    input  wire        cpu_rw,
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    output wire [31:0] cpu_rdata,
    output wire        cpu_ready,

    // ---- Main memory interface ----
    input  wire         mem_ready,
    input  wire [511:0] mem_rdata,
    output wire         mem_req,
    output wire         mem_rw,
    output wire [31:0]  mem_addr,
    output wire [511:0] mem_wdata
);

    // -----------------------------------------------------------------------
    // Address decoder wires (not strictly needed at top-level since the
    // controller decodes internally, but exposed here for clarity/debug)
    // -----------------------------------------------------------------------
    wire [TAG_W-1:0] dec_tag;
    wire [6:0]       dec_set;
    wire [4:0]       dec_offset;
    wire [1:0]       dec_byte;

    // Address decoder: splits cpu_addr into tag / set / offset / byte fields
    address_decoder u_addr_dec (
        .addr        (cpu_addr),
        .tag         (dec_tag),
        .set_index   (dec_set),
        .block_offset(dec_offset),
        .byte_offset (dec_byte)
    );

    // -----------------------------------------------------------------------
    // Wires between cache_controller and lru_controller
    // -----------------------------------------------------------------------
    wire        lru_access_valid;
    wire [6:0]  lru_access_set;
    wire [1:0]  lru_access_way;
    wire [6:0]  lru_query_set;
    wire [1:0]  lru_way;

    // LRU controller: tracks age of each way per set, outputs eviction candidate
    lru_controller #(
        .NUM_SETS(NUM_SETS),
        .NUM_WAYS(NUM_WAYS)
    ) u_lru (
        .clk          (clk),
        .rst          (rst),
        .access_valid (lru_access_valid),
        .access_set   (lru_access_set),
        .access_way   (lru_access_way),
        .query_set    (lru_query_set),
        .lru_way      (lru_way)
    );

    // -----------------------------------------------------------------------
    // Wires between cache_controller and cache_memory
    // -----------------------------------------------------------------------
    wire [6:0]  cm_r_set;

    wire        cm_valid0, cm_dirty0;
    wire [TAG_W-1:0]      cm_tag0;
    wire [BLOCK_BITS-1:0] cm_data0;

    wire        cm_valid1, cm_dirty1;
    wire [TAG_W-1:0]      cm_tag1;
    wire [BLOCK_BITS-1:0] cm_data1;

    wire        cm_valid2, cm_dirty2;
    wire [TAG_W-1:0]      cm_tag2;
    wire [BLOCK_BITS-1:0] cm_data2;

    wire        cm_valid3, cm_dirty3;
    wire [TAG_W-1:0]      cm_tag3;
    wire [BLOCK_BITS-1:0] cm_data3;

    wire         cm_w_en;
    wire [6:0]   cm_w_set;
    wire [1:0]   cm_w_way;
    wire         cm_w_valid, cm_w_dirty;
    wire [TAG_W-1:0]      cm_w_tag;
    wire [BLOCK_BITS-1:0] cm_w_data;

    wire         cm_ww_en;
    wire [6:0]   cm_ww_set;
    wire [1:0]   cm_ww_way;
    wire [4:0]   cm_ww_offset;
    wire [31:0]  cm_ww_word;

    // Cache memory: stores all tag/valid/dirty/data for all sets and ways
    cache_memory #(
        .NUM_SETS  (NUM_SETS),
        .NUM_WAYS  (NUM_WAYS),
        .TAG_W     (TAG_W),
        .BLOCK_BITS(BLOCK_BITS)
    ) u_cache_mem (
        .clk       (clk),
        // Read port
        .r_set     (cm_r_set),
        .r_valid0  (cm_valid0), .r_dirty0(cm_dirty0),
        .r_tag0    (cm_tag0),   .r_data0 (cm_data0),
        .r_valid1  (cm_valid1), .r_dirty1(cm_dirty1),
        .r_tag1    (cm_tag1),   .r_data1 (cm_data1),
        .r_valid2  (cm_valid2), .r_dirty2(cm_dirty2),
        .r_tag2    (cm_tag2),   .r_data2 (cm_data2),
        .r_valid3  (cm_valid3), .r_dirty3(cm_dirty3),
        .r_tag3    (cm_tag3),   .r_data3 (cm_data3),
        // Full-block write
        .w_en      (cm_w_en),
        .w_set     (cm_w_set),
        .w_way     (cm_w_way),
        .w_valid   (cm_w_valid),
        .w_dirty   (cm_w_dirty),
        .w_tag     (cm_w_tag),
        .w_data    (cm_w_data),
        // Word write
        .ww_en     (cm_ww_en),
        .ww_set    (cm_ww_set),
        .ww_way    (cm_ww_way),
        .ww_offset (cm_ww_offset),
        .ww_word   (cm_ww_word)
    );

    // Cache controller FSM: handles all hit/miss/evict decisions and sequencing
    cache_controller #(
        .NUM_SETS  (NUM_SETS),
        .NUM_WAYS  (NUM_WAYS),
        .TAG_W     (TAG_W),
        .BLOCK_BITS(BLOCK_BITS)
    ) u_ctrl (
        .clk              (clk),
        .rst              (rst),
        // CPU
        .cpu_req          (cpu_req),
        .cpu_rw           (cpu_rw),
        .cpu_addr         (cpu_addr),
        .cpu_wdata        (cpu_wdata),
        .cpu_rdata        (cpu_rdata),
        .cpu_ready        (cpu_ready),
        // Memory
        .mem_ready        (mem_ready),
        .mem_rdata        (mem_rdata),
        .mem_req          (mem_req),
        .mem_rw           (mem_rw),
        .mem_addr         (mem_addr),
        .mem_wdata        (mem_wdata),
        // Cache memory – per-way data
        .cm_valid0        (cm_valid0), .cm_dirty0(cm_dirty0),
        .cm_tag0          (cm_tag0),   .cm_data0 (cm_data0),
        .cm_valid1        (cm_valid1), .cm_dirty1(cm_dirty1),
        .cm_tag1          (cm_tag1),   .cm_data1 (cm_data1),
        .cm_valid2        (cm_valid2), .cm_dirty2(cm_dirty2),
        .cm_tag2          (cm_tag2),   .cm_data2 (cm_data2),
        .cm_valid3        (cm_valid3), .cm_dirty3(cm_dirty3),
        .cm_tag3          (cm_tag3),   .cm_data3 (cm_data3),
        .cm_r_set         (cm_r_set),
        // Cache memory – write ports
        .cm_w_en          (cm_w_en),
        .cm_w_set         (cm_w_set),
        .cm_w_way         (cm_w_way),
        .cm_w_valid       (cm_w_valid),
        .cm_w_dirty       (cm_w_dirty),
        .cm_w_tag         (cm_w_tag),
        .cm_w_data        (cm_w_data),
        .cm_ww_en         (cm_ww_en),
        .cm_ww_set        (cm_ww_set),
        .cm_ww_way        (cm_ww_way),
        .cm_ww_offset     (cm_ww_offset),
        .cm_ww_word       (cm_ww_word),
        // LRU
        .lru_access_valid (lru_access_valid),
        .lru_access_set   (lru_access_set),
        .lru_access_way   (lru_access_way),
        .lru_query_set    (lru_query_set),
        .lru_way          (lru_way)
    );

endmodule
