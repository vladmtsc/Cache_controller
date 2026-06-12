// cache_memory.v
// 128×4-way SRAM: valid (1b), dirty (1b), tag (18b), data (512b) per line.
// Read: combinational, all 4 ways in parallel.
// Write: full-line (fill/evict) or single-word (write-hit).

`timescale 1ns/1ps

module cache_memory #(
    parameter NUM_SETS   = 128,
    parameter NUM_WAYS   = 4,
    parameter TAG_W      = 18,
    parameter BLOCK_BITS = 512    // 64 bytes × 8
)(
    input  wire clk,

    // Read port: all 4 ways for r_set, combinational
    input  wire [6:0]  r_set,

    output wire        r_valid0, r_dirty0,
    output wire [TAG_W-1:0]      r_tag0,
    output wire [BLOCK_BITS-1:0] r_data0,

    output wire        r_valid1, r_dirty1,
    output wire [TAG_W-1:0]      r_tag1,
    output wire [BLOCK_BITS-1:0] r_data1,

    output wire        r_valid2, r_dirty2,
    output wire [TAG_W-1:0]      r_tag2,
    output wire [BLOCK_BITS-1:0] r_data2,

    output wire        r_valid3, r_dirty3,
    output wire [TAG_W-1:0]      r_tag3,
    output wire [BLOCK_BITS-1:0] r_data3,

    // Full-line write port (synchronous)
    input  wire        w_en,
    input  wire [6:0]  w_set,
    input  wire [1:0]  w_way,
    input  wire        w_valid,
    input  wire        w_dirty,
    input  wire [TAG_W-1:0]      w_tag,
    input  wire [BLOCK_BITS-1:0] w_data,

    // Single-word write port (synchronous)
    input  wire        ww_en,
    input  wire [6:0]  ww_set,
    input  wire [1:0]  ww_way,
    input  wire [4:0]  ww_offset,   // word index 0–15 within the 64-byte block
    input  wire [31:0] ww_word,

    // Testbench preload port — bypasses normal write paths for state injection
    input  wire                  preload_en,
    input  wire [6:0]            preload_set,
    input  wire [1:0]            preload_way,
    input  wire                  preload_valid,
    input  wire                  preload_dirty,
    input  wire [TAG_W-1:0]      preload_tag,
    input  wire [BLOCK_BITS-1:0] preload_data
);

    reg                  valid_a [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg                  dirty_a [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [TAG_W-1:0]      tag_a   [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [BLOCK_BITS-1:0] data_a  [0:NUM_SETS-1][0:NUM_WAYS-1];

    always @(posedge clk) begin
        if (preload_en) begin
            valid_a[preload_set][preload_way] <= preload_valid;
            dirty_a[preload_set][preload_way] <= preload_dirty;
            tag_a  [preload_set][preload_way] <= preload_tag;
            data_a [preload_set][preload_way] <= preload_data;
        end
        if (w_en) begin
            valid_a[w_set][w_way] <= w_valid;
            dirty_a[w_set][w_way] <= w_dirty;
            tag_a  [w_set][w_way] <= w_tag;
            data_a [w_set][w_way] <= w_data;
        end
        if (ww_en) begin
            dirty_a[ww_set][ww_way]                      <= 1'b1; // any CPU write dirties the line
            data_a [ww_set][ww_way][ww_offset*32 +: 32]  <= ww_word;
        end
    end

    assign r_valid0 = valid_a[r_set][0];
    assign r_dirty0 = dirty_a[r_set][0];
    assign r_tag0   = tag_a  [r_set][0];
    assign r_data0  = data_a [r_set][0];

    assign r_valid1 = valid_a[r_set][1];
    assign r_dirty1 = dirty_a[r_set][1];
    assign r_tag1   = tag_a  [r_set][1];
    assign r_data1  = data_a [r_set][1];

    assign r_valid2 = valid_a[r_set][2];
    assign r_dirty2 = dirty_a[r_set][2];
    assign r_tag2   = tag_a  [r_set][2];
    assign r_data2  = data_a [r_set][2];

    assign r_valid3 = valid_a[r_set][3];
    assign r_dirty3 = dirty_a[r_set][3];
    assign r_tag3   = tag_a  [r_set][3];
    assign r_data3  = data_a [r_set][3];

endmodule
