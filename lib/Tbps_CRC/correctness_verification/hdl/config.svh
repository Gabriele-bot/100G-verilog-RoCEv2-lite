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

/*- simulation -*/
`ifndef N_MESSAGE
    `define N_MESSAGE 100
`endif
`ifndef MESSAGE_LEN_MIN
    `define MESSAGE_LEN_MIN 1
`endif
`ifndef MESSAGE_LEN_MAX
    `define MESSAGE_LEN_MAX 1500
`endif
`ifndef flitEn_ratio
    `define flitEn_ratio 0.8 //80% of the flits are valid
`endif

/*- hardware implementation -*/
`ifndef PKT_LIMIT
    `define PKT_LIMIT 10
`endif
`ifndef BYTE_BITS
    `define BYTE_BITS 11 //Max message size = 2^11 bytes
`endif