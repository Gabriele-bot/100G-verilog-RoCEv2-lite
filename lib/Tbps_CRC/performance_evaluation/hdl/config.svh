/*- general setup -*/
`ifndef DWIDTH
    `define DWIDTH 512
`endif
`ifndef CRC_WIDTH
    `define CRC_WIDTH 32
`endif
`ifndef PIPE_LVL
    `define PIPE_LVL 0
`endif
`ifndef CRC_POLY
    `define CRC_POLY 32'h04C11DB7
`endif
`ifndef INIT
    `define INIT 32'hffffffff
`endif
`ifndef XOR_OUT
    `define XOR_OUT 32'hffffffff
`endif
`ifndef REFIN
    `define REFIN 1'b1
`endif
`ifndef REFOUT
    `define REFOUT 1'b1
`endif
