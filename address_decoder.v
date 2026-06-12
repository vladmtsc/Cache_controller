// address_decoder.v
// [31:14]=tag (18b)  [13:7]=set (7b)  [6:2]=word offset (5b)  [1:0]=byte (2b)

`timescale 1ns/1ps

module address_decoder (
    input  wire [31:0] addr,

    output wire [17:0] tag,
    output wire [6:0]  set_index,
    output wire [4:0]  block_offset, // addr[6:2]: 5 bits index 16 words in a 64-byte block
    output wire [1:0]  byte_offset
);

    assign tag          = addr[31:14];
    assign set_index    = addr[13:7];
    assign block_offset = addr[6:2];
    assign byte_offset  = addr[1:0];

endmodule
