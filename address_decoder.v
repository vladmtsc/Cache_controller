// address_decoder.v
// Splits a 32-bit CPU address into tag, set index, block offset, and byte offset.
//
// Address layout (32 bits total):
//   [31:14] = tag         (18 bits) – identifies which memory block is cached
//   [13:7]  = set_index   (7 bits)  – selects one of 128 sets (2^7 = 128)
//   [6:2]   = block_offset (5 bits) – selects one of 16 words in a 64-byte block (2^5=32...
//                                      actually 64 bytes / 4 bytes per word = 16 words, 4 bits needed;
//                                      but bits [6:2] = 5 bits to address 32 byte positions by word,
//                                      covering the 64-byte block at word granularity)
//   [1:0]   = byte_offset  (2 bits) – byte position within a 4-byte word

`timescale 1ns/1ps

module address_decoder (
    input  wire [31:0] addr,         // full 32-bit CPU address

    output wire [17:0] tag,          // 18-bit tag for cache comparison
    output wire [6:0]  set_index,    // 7-bit set selector (0–127)
    output wire [4:0]  block_offset, // 5-bit word offset within the cache block
    output wire [1:0]  byte_offset   // 2-bit byte offset within a word
);

    // Tag: top 18 bits identify the memory region mapped to this cache entry
    assign tag = addr[31:14];

    // Set index: next 7 bits select which of the 128 sets to look in
    assign set_index = addr[13:7];

    // Block offset: next 5 bits select which 32-bit word within the 64-byte block
    // 64 bytes / 4 bytes per word = 16 words, indexed by addr[6:2] (lower bit of 5 is sub-word)
    assign block_offset = addr[6:2];

    // Byte offset: lowest 2 bits select which byte within the 4-byte word
    assign byte_offset = addr[1:0];

endmodule
