// lru_controller.v
// Tracks LRU (Least Recently Used) order for a 4-way set-associative cache.
//
// Each way in each set has a 2-bit age counter:
//   0 = most recently used
//   3 = least recently used (eviction candidate)
//
// On every access, the accessed way's age becomes 0,
// and any other way whose age was less than the accessed way's old age gets incremented.
// This keeps all 4 ages distinct and in range [0..3] at all times.

`timescale 1ns/1ps

module lru_controller #(
    parameter NUM_SETS = 128,   // number of cache sets
    parameter NUM_WAYS = 4      // associativity
)(
    input  wire                   clk,
    input  wire                   rst,

    // Access interface: update LRU when a hit or allocate occurs
    input  wire                   access_valid,          // 1 = perform an LRU update this cycle
    input  wire [$clog2(NUM_SETS)-1:0] access_set,      // which set was accessed
    input  wire [$clog2(NUM_WAYS)-1:0] access_way,      // which way was accessed (hit or fill)

    // Query interface: which way should be evicted?
    input  wire [$clog2(NUM_SETS)-1:0] query_set,       // set to query for eviction victim
    output reg  [$clog2(NUM_WAYS)-1:0] lru_way          // way with age = 3 (LRU victim)
);

    // 2-bit age per way per set: age[set][way]
    reg [1:0] age [0:NUM_SETS-1][0:NUM_WAYS-1];

    integer i, j;

    // -----------------------------------------------------------------------
    // On reset: initialize ages to 0,1,2,3 so way 3 is first eviction target
    // On access: update ages for the accessed set
    // -----------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Initialize each set so way 0 is MRU and way 3 is LRU
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                age[i][0] <= 2'd0;
                age[i][1] <= 2'd1;
                age[i][2] <= 2'd2;
                age[i][3] <= 2'd3;
            end
        end else if (access_valid) begin
            // Save the old age of the accessed way before overwriting it
            // Then update all other ways: if their age < old age of accessed way, increment
            begin : update_lru
                reg [1:0] old_age;
                old_age = age[access_set][access_way];

                // Increment ages of ways that were more recently used than the accessed way
                for (j = 0; j < NUM_WAYS; j = j + 1) begin
                    if (j != access_way && age[access_set][j] < old_age) begin
                        age[access_set][j] <= age[access_set][j] + 2'd1;
                    end
                end

                // Mark the accessed way as most recently used
                age[access_set][access_way] <= 2'd0;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Combinationally find which way has age == 3 (the LRU victim) for query_set
    // -----------------------------------------------------------------------
    always @(*) begin
        lru_way = 2'd0; // default to way 0 if not found (should always find age==3)
        for (j = 0; j < NUM_WAYS; j = j + 1) begin
            if (age[query_set][j] == 2'd3) begin
                lru_way = j[1:0];
            end
        end
    end

endmodule
