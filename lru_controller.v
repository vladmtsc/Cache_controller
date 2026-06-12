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
    output reg  [$clog2(NUM_WAYS)-1:0] lru_way
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

    // Find the way with age==3 for query_set (eviction victim)
    always @(*) begin
        lru_way = 2'd0; // fallback; a valid age==3 entry always exists after reset
        for (j = 0; j < NUM_WAYS; j = j + 1) begin
            if (age[query_set][j] == 2'd3)
                lru_way = j[1:0];
        end
    end

endmodule
