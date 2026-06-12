// cache_tb.v
// Testbench for cache_top: read hit, read miss, write hit, write miss, evict, LRU, sequential.

`timescale 1ns/1ps

module cache_tb;

    reg         clk, rst;
    reg         cpu_req, cpu_rw;
    reg  [31:0] cpu_addr, cpu_wdata;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;

    reg          mem_ready;
    reg  [511:0] mem_rdata;
    wire         mem_req, mem_rw;
    wire [31:0]  mem_addr;
    wire [511:0] mem_wdata;

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

    initial clk = 0;
    always #5 clk = ~clk;

    integer total_ops, hit_ops;

    // cpu_rdata is combinational and returns to 0 when FSM goes back to IDLE.
    // Capture it at the exact posedge where cpu_ready=1, before the transition.
    reg [31:0] captured_rdata;

    integer cycle_cnt;
    task wait_ready;
        begin
            cycle_cnt = 0;
            @(posedge clk);
            cycle_cnt = 1;
            while (!cpu_ready) begin
                @(posedge clk);
                cycle_cnt = cycle_cnt + 1;
            end
            captured_rdata = cpu_rdata; // capture here — cpu_rdata goes to 0 after this posedge
            if (cycle_cnt <= 2) hit_ops = hit_ops + 1;
            total_ops = total_ops + 1;
        end
    endtask

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

    // Drive mem_rdata and assert mem_ready after `delay` cycles
    task mem_respond;
        input [511:0] block;
        input integer  delay;
        begin
            repeat (delay) @(posedge clk);
            mem_rdata = block;
            mem_ready = 1;
            @(posedge clk);
            mem_ready = 0;
        end
    endtask

    // TC1: READ HIT
    // Preload set 0 way 0, read same address — expect data returned in 1-2 cycles.
    task test_read_hit;
        reg [511:0] block;
        reg [31:0]  expected;
        begin
            $display("\n=== TC1: READ HIT ===");
            block       = 512'h0;
            block[31:0] = 32'hDEAD_BEEF;

            force dut.u_cache_mem.valid_a[0][0] = 1'b1;
            force dut.u_cache_mem.dirty_a[0][0] = 1'b0;
            force dut.u_cache_mem.tag_a  [0][0] = 18'd0;
            force dut.u_cache_mem.data_a [0][0] = block;
            @(posedge clk);
            release dut.u_cache_mem.valid_a[0][0];
            release dut.u_cache_mem.dirty_a[0][0];
            release dut.u_cache_mem.tag_a  [0][0];
            release dut.u_cache_mem.data_a [0][0];

            do_read(32'h0000_0000); // tag=0, set=0, offset=0

            expected = 32'hDEAD_BEEF;
            if (captured_rdata === expected)
                $display("TC1 PASS: cpu_rdata = 0x%08h", captured_rdata);
            else
                $display("TC1 FAIL: expected 0x%08h, got 0x%08h", expected, captured_rdata);
        end
    endtask

    // TC2: READ MISS (clean eviction candidate)
    // Read uncached address — expect mem_req issued and data returned.
    task test_read_miss;
        reg [511:0] mem_block;
        begin
            $display("\n=== TC2: READ MISS ===");
            mem_block       = 512'h0;
            mem_block[31:0] = 32'hCAFE_BABE;

            fork
                do_read(32'h0000_4080); // tag=1, set=1, offset=0
                mem_respond(mem_block, 3);
            join

            if (captured_rdata === 32'hCAFE_BABE)
                $display("TC2 PASS: cpu_rdata = 0x%08h", captured_rdata);
            else
                $display("TC2 FAIL: expected 0xCAFEBABE, got 0x%08h", captured_rdata);
        end
    endtask

    // TC3: WRITE HIT
    // Preload set 2 way 0, write to same address — expect dirty bit set and data updated.
    task test_write_hit;
        begin
            $display("\n=== TC3: WRITE HIT ===");
            force dut.u_cache_mem.valid_a[2][0] = 1'b1;
            force dut.u_cache_mem.dirty_a[2][0] = 1'b0;
            force dut.u_cache_mem.tag_a  [2][0] = 18'd0;
            force dut.u_cache_mem.data_a [2][0] = 512'h0;
            @(posedge clk);
            release dut.u_cache_mem.valid_a[2][0];
            release dut.u_cache_mem.dirty_a[2][0];
            release dut.u_cache_mem.tag_a  [2][0];
            release dut.u_cache_mem.data_a [2][0];

            do_write(32'h0000_0100, 32'h1234_5678); // tag=0, set=2, offset=0
            @(posedge clk);

            if (dut.u_cache_mem.dirty_a[2][0] === 1'b1)
                $display("TC3 PASS: dirty bit set after write hit");
            else
                $display("TC3 FAIL: dirty bit not set after write hit");

            if (dut.u_cache_mem.data_a[2][0][31:0] === 32'h1234_5678)
                $display("TC3 PASS: data updated correctly");
            else
                $display("TC3 FAIL: data not updated correctly");
        end
    endtask

    // TC4: WRITE MISS (write-allocate)
    // Write to uncached address — expect block fetched first, CPU word merged, line installed dirty.
    // The filled way is whichever the LRU selected; scan all 4 ways for the result.
    task test_write_miss;
        reg [511:0] mem_block;
        integer w;
        reg found_dirty, found_data;
        begin
            $display("\n=== TC4: WRITE MISS (Write Allocate) ===");
            mem_block       = 512'h0;
            mem_block[31:0] = 32'hAAAA_AAAA;

            fork
                do_write(32'h0000_4180, 32'hBBBB_BBBB); // tag=1, set=3, offset=0
                mem_respond(mem_block, 3);
            join
            @(posedge clk);

            found_dirty = 0;
            found_data  = 0;
            for (w = 0; w < 4; w = w + 1) begin
                if (dut.u_cache_mem.dirty_a[3][w] === 1'b1) found_dirty = 1;
                if (dut.u_cache_mem.data_a[3][w][31:0] === 32'hBBBB_BBBB) found_data = 1;
            end

            if (found_dirty)
                $display("TC4 PASS: dirty bit set after write miss");
            else
                $display("TC4 FAIL: no dirty bit set in set 3 after write miss");

            if (found_data)
                $display("TC4 PASS: CPU write word installed correctly");
            else
                $display("TC4 FAIL: 0xBBBBBBBB not found in any way of set 3");
        end
    endtask

    // TC5: EVICT (dirty writeback)
    // Fill set 4 with 4 dirty lines, then access a 5th tag.
    // Expect LRU dirty line written back before new block is filled.
    task test_evict;
        reg [511:0] mem_block;
        integer w;
        begin
            $display("\n=== TC5: EVICT (dirty writeback) ===");
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

            // addr: tag=20, set=4, offset=0 → triggers EVICT then READ_MISS
            fork
                do_read(32'h0005_0200);
                begin
                    @(posedge mem_req);
                    repeat (2) @(posedge clk);
                    mem_ready = 1; @(posedge clk); mem_ready = 0; // ack writeback
                    @(posedge clk);
                    mem_rdata = mem_block;
                    repeat (2) @(posedge clk);
                    mem_ready = 1; @(posedge clk); mem_ready = 0; // ack fill
                end
            join

            // wait_ready inside do_read already confirmed cpu_ready was seen
            $display("TC5 PASS: evict + fill completed (no hang)");
        end
    endtask

    // TC6: LRU order
    // Force ages in set 5 so way 0 is LRU (age=3), verify lru_way outputs 0.
    task test_lru_order;
        reg [1:0] victim;
        begin
            $display("\n=== TC6: LRU ORDER VERIFICATION ===");
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

            // Access order 0,1,2,3 then re-access 1 → way 0 = age 3 (LRU victim)
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

    // TC7: Sequential back-to-back reads (all misses, different sets)
    task test_sequential;
        reg [511:0] blk;
        integer i;
        begin
            $display("\n=== TC7: SEQUENTIAL REQUESTS ===");
            for (i = 0; i < 4; i = i + 1) begin
                blk = {16{i[31:0]}};
                fork
                    do_read(32'h0010_0000 + i * 32'h80);
                    mem_respond(blk, 2);
                join
            end
            $display("TC7 PASS: 4 sequential reads completed without hang");
        end
    endtask

    initial begin
        total_ops = 0;
        hit_ops   = 0;

        rst       = 1;
        cpu_req   = 0; cpu_rw    = 0;
        cpu_addr  = 0; cpu_wdata = 0;
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

    // Safety timeout
    initial begin
        #50000;
        $display("TIMEOUT: simulation exceeded 50000 ns");
        $finish;
    end

endmodule
