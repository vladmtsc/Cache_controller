// cache_tb.v
// Testbench for the 4-way set-associative cache controller.
// Tests: read hit, read miss, write hit, write miss, evict, LRU order, sequential.

`timescale 1ns/1ps

module cache_tb;

    // -----------------------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------------------
    reg         clk, rst;
    reg         cpu_req, cpu_rw;
    reg  [31:0] cpu_addr, cpu_wdata;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;

    // Simulated main memory interface
    reg         mem_ready;
    reg  [511:0] mem_rdata;
    wire         mem_req, mem_rw;
    wire [31:0]  mem_addr;
    wire [511:0] mem_wdata;

    // -----------------------------------------------------------------------
    // DUT instantiation
    // -----------------------------------------------------------------------
    cache_top dut (
        .clk      (clk),
        .rst      (rst),
        .cpu_req  (cpu_req),
        .cpu_rw   (cpu_rw),
        .cpu_addr (cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready),
        .mem_ready(mem_ready),
        .mem_rdata(mem_rdata),
        .mem_req  (mem_req),
        .mem_rw   (mem_rw),
        .mem_addr (mem_addr),
        .mem_wdata(mem_wdata)
    );

    // -----------------------------------------------------------------------
    // Clock: 10 ns period
    // -----------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // Statistics counters
    // -----------------------------------------------------------------------
    integer total_ops, hit_ops;

    // -----------------------------------------------------------------------
    // Helper tasks
    // -----------------------------------------------------------------------

    // Wait for cpu_ready, track hit (ready within 2 cycles of asserting cpu_req = hit)
    integer cycle_cnt;
    task wait_ready;
        begin
            cycle_cnt = 0;
            @(posedge clk); // first clock edge after request
            cycle_cnt = 1;
            while (!cpu_ready) begin
                @(posedge clk);
                cycle_cnt = cycle_cnt + 1;
            end
            if (cycle_cnt <= 2) hit_ops = hit_ops + 1; // hits complete in 1-2 cycles
            total_ops = total_ops + 1;
        end
    endtask

    // Issue a read and wait for completion
    task do_read;
        input [31:0] addr;
        begin
            @(negedge clk);
            cpu_req  = 1;
            cpu_rw   = 0;
            cpu_addr = addr;
            wait_ready;
            @(negedge clk);
            cpu_req = 0;
        end
    endtask

    // Issue a write and wait for completion
    task do_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(negedge clk);
            cpu_req   = 1;
            cpu_rw    = 1;
            cpu_addr  = addr;
            cpu_wdata = data;
            wait_ready;
            @(negedge clk);
            cpu_req = 0;
        end
    endtask

    // Simulate memory responding with a block after N cycles
    task mem_respond;
        input [511:0] block;
        input integer  delay;
        integer i;
        begin
            repeat (delay) @(posedge clk);
            mem_rdata = block;
            mem_ready = 1;
            @(posedge clk);
            mem_ready = 0;
        end
    endtask

    // -----------------------------------------------------------------------
    // Test Case 1 – READ HIT
    // Preload set 0, way 0 with a known block, then read the same address.
    // Expect cpu_ready in 1 cycle and correct data returned.
    // -----------------------------------------------------------------------
    task test_read_hit;
        reg [511:0] block;
        reg [31:0]  expected;
        begin
            $display("\n=== TC1: READ HIT ===");
            // Build a 512-bit block where word 0 = 0xDEADBEEF
            block          = 512'h0;
            block[31:0]    = 32'hDEAD_BEEF;

            // Manually preload cache_memory way 0, set 0
            // Tag for addr 0x00000000: bits[31:14] = 0
            // Use cache_memory's write port directly via force (simulation only)
            force dut.u_cache_mem.valid_a[0][0] = 1'b1;
            force dut.u_cache_mem.dirty_a[0][0] = 1'b0;
            force dut.u_cache_mem.tag_a  [0][0] = 18'd0;
            force dut.u_cache_mem.data_a [0][0] = block;
            @(posedge clk);
            release dut.u_cache_mem.valid_a[0][0];
            release dut.u_cache_mem.dirty_a[0][0];
            release dut.u_cache_mem.tag_a  [0][0];
            release dut.u_cache_mem.data_a [0][0];

            do_read(32'h0000_0000);  // address maps to set 0, offset 0

            expected = 32'hDEAD_BEEF;
            if (cpu_rdata === expected)
                $display("TC1 PASS: cpu_rdata = 0x%08h", cpu_rdata);
            else
                $display("TC1 FAIL: expected 0x%08h, got 0x%08h", expected, cpu_rdata);
        end
    endtask

    // -----------------------------------------------------------------------
    // Test Case 2 – READ MISS (clean eviction candidate)
    // Read an address not in cache. Expect mem_req issued and data returned.
    // -----------------------------------------------------------------------
    task test_read_miss;
        reg [511:0] mem_block;
        begin
            $display("\n=== TC2: READ MISS ===");
            // Address: set 1, offset 0, tag 1
            // addr[31:14]=1, addr[13:7]=1, addr[6:0]=0 → 0x0000_0080
            mem_block       = 512'h0;
            mem_block[31:0] = 32'hCAFE_BABE;

            fork
                do_read(32'h0000_4080); // tag=1, set=1, offset=0
                mem_respond(mem_block, 3);
            join

            if (cpu_rdata === 32'hCAFE_BABE)
                $display("TC2 PASS: cpu_rdata = 0x%08h", cpu_rdata);
            else
                $display("TC2 FAIL: expected 0xCAFEBABE, got 0x%08h", cpu_rdata);
        end
    endtask

    // -----------------------------------------------------------------------
    // Test Case 3 – WRITE HIT
    // After TC1 preload, write to the same address and verify dirty bit set.
    // -----------------------------------------------------------------------
    task test_write_hit;
        begin
            $display("\n=== TC3: WRITE HIT ===");
            // Preload set 2, way 0
            force dut.u_cache_mem.valid_a[2][0] = 1'b1;
            force dut.u_cache_mem.dirty_a[2][0] = 1'b0;
            force dut.u_cache_mem.tag_a  [2][0] = 18'd0;
            force dut.u_cache_mem.data_a [2][0] = 512'h0;
            @(posedge clk);
            release dut.u_cache_mem.valid_a[2][0];
            release dut.u_cache_mem.dirty_a[2][0];
            release dut.u_cache_mem.tag_a  [2][0];
            release dut.u_cache_mem.data_a [2][0];

            // addr: tag=0, set=2, offset=0 → 0x0000_0100
            do_write(32'h0000_0100, 32'h1234_5678);
            @(posedge clk);

            if (dut.u_cache_mem.dirty_a[2][0] === 1'b1)
                $display("TC3 PASS: dirty bit set after write hit");
            else
                $display("TC3 FAIL: dirty bit not set after write hit");

            // Verify data was updated
            if (dut.u_cache_mem.data_a[2][0][31:0] === 32'h1234_5678)
                $display("TC3 PASS: data updated correctly");
            else
                $display("TC3 FAIL: data not updated correctly");
        end
    endtask

    // -----------------------------------------------------------------------
    // Test Case 4 – WRITE MISS (Write Allocate)
    // Write to an address not in cache. Expect fetch first, then write applied.
    // -----------------------------------------------------------------------
    task test_write_miss;
        reg [511:0] mem_block;
        begin
            $display("\n=== TC4: WRITE MISS (Write Allocate) ===");
            // Use set 3, tag 1: addr 0x0000_4180 (tag=1, set=3, offset=0)
            mem_block       = 512'h0;
            mem_block[31:0] = 32'hAAAA_AAAA; // existing memory content

            fork
                do_write(32'h0000_4180, 32'hBBBB_BBBB);
                mem_respond(mem_block, 3);
            join
            @(posedge clk);

            // After write-miss, the cache line at set 3 should be dirty
            // and word 0 should be 0xBBBBBBBB (CPU write merged over fetch)
            if (dut.u_cache_mem.dirty_a[3][0] === 1'b1)
                $display("TC4 PASS: dirty bit set after write miss");
            else
                $display("TC4 FAIL: dirty bit not set (check evict_way)");

            if (dut.u_cache_mem.data_a[3][0][31:0] === 32'hBBBB_BBBB)
                $display("TC4 PASS: CPU write word installed correctly");
            else
                $display("TC4 FAIL: expected 0xBBBBBBBB, got 0x%08h",
                         dut.u_cache_mem.data_a[3][0][31:0]);
        end
    endtask

    // -----------------------------------------------------------------------
    // Test Case 5 – EVICT (dirty writeback)
    // Fill set 4 ways 0-3 with dirty lines, then access a 5th tag in set 4.
    // Expect the LRU (dirtiest) line to be written back before fill.
    // -----------------------------------------------------------------------
    task test_evict;
        reg [511:0] mem_block;
        integer w;
        begin
            $display("\n=== TC5: EVICT (dirty writeback) ===");
            // Force all 4 ways of set 4 to be dirty with unique tags
            for (w = 0; w < 4; w = w + 1) begin
                force dut.u_cache_mem.valid_a[4][w] = 1'b1;
                force dut.u_cache_mem.dirty_a[4][w] = 1'b1;
                force dut.u_cache_mem.tag_a  [4][w] = w[17:0] + 18'd10;
                force dut.u_cache_mem.data_a [4][w] = {16{w[31:0]}};
                @(posedge clk);
                release dut.u_cache_mem.valid_a[4][w];
                release dut.u_cache_mem.dirty_a[4][w];
                release dut.u_cache_mem.tag_a  [4][w];
                release dut.u_cache_mem.data_a [4][w];
            end

            mem_block = 512'hFF;

            // Access a new tag (tag=20) in set 4 → triggers EVICT then READ_MISS
            // addr: tag=20, set=4, offset=0
            // tag=20 → bits[31:14] = 20 → addr = 20<<14 | 4<<7 = 0x50200
            fork
                do_read(32'h0005_0200);
                begin
                    // Wait for FSM to enter EVICT (mem_req goes high with mem_rw=1)
                    @(posedge mem_req);
                    repeat (2) @(posedge clk);
                    // Acknowledge eviction writeback
                    mem_ready = 1; @(posedge clk); mem_ready = 0;
                    // FSM now moves to READ_MISS; mem_req stays high but mem_rw=0
                    // Wait 1 cycle for state transition, then serve the fill
                    @(posedge clk);
                    mem_rdata = mem_block;
                    repeat (2) @(posedge clk);
                    // Acknowledge block fill
                    mem_ready = 1; @(posedge clk); mem_ready = 0;
                end
            join

            $display("TC5: eviction sequence completed, cpu_ready=%b", cpu_ready);
            if (cpu_ready)
                $display("TC5 PASS: evict + fill completed successfully");
            else
                $display("TC5 FAIL: cpu_ready not asserted after evict+fill");
        end
    endtask

    // -----------------------------------------------------------------------
    // Test Case 6 – LRU order verification
    // Access ways in order 0,1,2,3, re-access way 1. Next evict victim = way 0.
    // -----------------------------------------------------------------------
    task test_lru_order;
        reg [1:0] victim;
        begin
            $display("\n=== TC6: LRU ORDER VERIFICATION ===");
            // Force all 4 ways of set 5 valid, clean, with distinct tags
            force dut.u_cache_mem.valid_a[5][0] = 1'b1;
            force dut.u_cache_mem.dirty_a[5][0] = 1'b0;
            force dut.u_cache_mem.tag_a  [5][0] = 18'd100;
            force dut.u_cache_mem.data_a [5][0] = 512'h0;

            force dut.u_cache_mem.valid_a[5][1] = 1'b1;
            force dut.u_cache_mem.dirty_a[5][1] = 1'b0;
            force dut.u_cache_mem.tag_a  [5][1] = 18'd101;
            force dut.u_cache_mem.data_a [5][1] = 512'h0;

            force dut.u_cache_mem.valid_a[5][2] = 1'b1;
            force dut.u_cache_mem.dirty_a[5][2] = 1'b0;
            force dut.u_cache_mem.tag_a  [5][2] = 18'd102;
            force dut.u_cache_mem.data_a [5][2] = 512'h0;

            force dut.u_cache_mem.valid_a[5][3] = 1'b1;
            force dut.u_cache_mem.dirty_a[5][3] = 1'b0;
            force dut.u_cache_mem.tag_a  [5][3] = 18'd103;
            force dut.u_cache_mem.data_a [5][3] = 512'h0;

            @(posedge clk);
            release dut.u_cache_mem.valid_a[5][0]; release dut.u_cache_mem.dirty_a[5][0];
            release dut.u_cache_mem.tag_a[5][0];   release dut.u_cache_mem.data_a[5][0];
            release dut.u_cache_mem.valid_a[5][1]; release dut.u_cache_mem.dirty_a[5][1];
            release dut.u_cache_mem.tag_a[5][1];   release dut.u_cache_mem.data_a[5][1];
            release dut.u_cache_mem.valid_a[5][2]; release dut.u_cache_mem.dirty_a[5][2];
            release dut.u_cache_mem.tag_a[5][2];   release dut.u_cache_mem.data_a[5][2];
            release dut.u_cache_mem.valid_a[5][3]; release dut.u_cache_mem.dirty_a[5][3];
            release dut.u_cache_mem.tag_a[5][3];   release dut.u_cache_mem.data_a[5][3];

            // Force LRU ages: access order 0,1,2,3 then re-access 1
            // After: way 0 = age 3 (LRU), way 2 = age 2, way 3 = age 1, way 1 = age 0 (MRU)
            force dut.u_lru.age[5][0] = 2'd3;
            force dut.u_lru.age[5][1] = 2'd0;
            force dut.u_lru.age[5][2] = 2'd2;
            force dut.u_lru.age[5][3] = 2'd1;
            @(posedge clk);
            release dut.u_lru.age[5][0];
            release dut.u_lru.age[5][1];
            release dut.u_lru.age[5][2];
            release dut.u_lru.age[5][3];
            @(posedge clk);

            victim = dut.u_ctrl.lru_way;
            $display("TC6: LRU victim way = %0d (expected 0)", victim);
            if (victim === 2'd0)
                $display("TC6 PASS: correct LRU eviction victim");
            else
                $display("TC6 FAIL: wrong victim, got way %0d", victim);
        end
    endtask

    // -----------------------------------------------------------------------
    // Test Case 7 – Sequential requests (back-to-back reads)
    // -----------------------------------------------------------------------
    task test_sequential;
        reg [511:0] blk;
        integer i;
        begin
            $display("\n=== TC7: SEQUENTIAL REQUESTS ===");
            // Read 4 different addresses back to back (all misses → fills)
            for (i = 0; i < 4; i = i + 1) begin
                blk = {16{i[31:0]}};
                fork
                    do_read(32'h0010_0000 + i * 32'h80);  // different sets
                    mem_respond(blk, 2);
                join
            end
            $display("TC7 PASS: 4 sequential reads completed without hang");
        end
    endtask

    // -----------------------------------------------------------------------
    // Main simulation flow
    // -----------------------------------------------------------------------
    initial begin
        total_ops = 0;
        hit_ops   = 0;

        // Reset sequence
        rst      = 1;
        cpu_req  = 0; cpu_rw = 0;
        cpu_addr = 0; cpu_wdata = 0;
        mem_ready = 0; mem_rdata = 512'h0;
        repeat (4) @(posedge clk);
        rst = 0;
        @(posedge clk);

        test_read_hit;
        test_read_miss;
        test_write_hit;
        test_write_miss;
        test_evict;
        test_lru_order;
        test_sequential;

        // -----------------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------------
        $display("\n========================================");
        $display("SIMULATION COMPLETE");
        $display("Total operations : %0d", total_ops);
        $display("Hits             : %0d", hit_ops);
        $display("Misses           : %0d", total_ops - hit_ops);
        if (total_ops > 0)
            $display("Hit Rate         : %0d%%", hit_ops * 100 / total_ops);
        $display("========================================\n");

        $finish;
    end

    // Safety timeout: end simulation after 50000 ns if hung
    initial begin
        #50000;
        $display("TIMEOUT: simulation exceeded 50000 ns");
        $finish;
    end

endmodule
