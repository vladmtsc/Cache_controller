// lru_controller.v
// 2-bit age counter per way: 0=MRU, 3=LRU (eviction target).
// On access: accessed way → age 0; ways with age < old_age get incremented.

`timescale 1ns/1ps

module lru_controller #(
    parameter NUM_SETS = 128,
    parameter NUM_WAYS = 4
)(
    input  wire                        clk,
    input  wire                        rst,
    input  wire                        access_valid,
    input  wire [$clog2(NUM_SETS)-1:0] access_set,
    input  wire [$clog2(NUM_WAYS)-1:0] access_way,
    input  wire [$clog2(NUM_SETS)-1:0] query_set,
    output reg  [$clog2(NUM_WAYS)-1:0] lru_way,

    // Testbench preload port — injects specific age values for state setup
    input  wire                        age_preload_en,
    input  wire [$clog2(NUM_SETS)-1:0] age_preload_set,
    input  wire [$clog2(NUM_WAYS)-1:0] age_preload_way,
    input  wire [1:0]                  age_preload_val
);

    reg [1:0] age [0:NUM_SETS-1][0:NUM_WAYS-1];

    integer i, j;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Initialize so way 0 is MRU and way 3 is first eviction target
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                age[i][0] <= 2'd0;
                age[i][1] <= 2'd1;
                age[i][2] <= 2'd2;
                age[i][3] <= 2'd3;
            end
        end else if (age_preload_en) begin
            age[age_preload_set][age_preload_way] <= age_preload_val;
        end else if (access_valid) begin
            begin : update_lru
                reg [1:0] old_age;
                old_age = age[access_set][access_way];
                for (j = 0; j < NUM_WAYS; j = j + 1) begin
                    if (j != access_way && age[access_set][j] < old_age)
                        age[access_set][j] <= age[access_set][j] + 2'd1;
                end
                age[access_set][access_way] <= 2'd0;
            end
        end
    end

    // Extract the 4 ages for query_set via continuous assignment so the
    // always block below can use a short, explicit sensitivity list instead
    // of @(*) (which Icarus expands to all 512 array entries).
    wire [1:0] q_age0 = age[query_set][0];
    wire [1:0] q_age1 = age[query_set][1];
    wire [1:0] q_age2 = age[query_set][2];
    wire [1:0] q_age3 = age[query_set][3];

    // Find the way with age==3 for query_set (eviction victim)
    always @(q_age0 or q_age1 or q_age2 or q_age3) begin
        lru_way = 2'd0; // fallback; a valid age==3 entry always exists after reset
        if (q_age0 == 2'd3) lru_way = 2'd0;
        if (q_age1 == 2'd3) lru_way = 2'd1;
        if (q_age2 == 2'd3) lru_way = 2'd2;
        if (q_age3 == 2'd3) lru_way = 2'd3;
    end

endmodule
