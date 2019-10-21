`define IPV4_WIDTH 32
`define MASK_WIDTH 8
`define BYTE_WIDTH 8

/* Routing Table */
`define NUM_CHILDS 16
`define NUM_NODES 1024
`define NODE_INDEX_WIDTH 16
`define BLCK_COVER_WIDTH 2
`define BLCK_INDEX_WIDTH 20     // NODE_INDEX_WIDTH + log(NUM_CHILDS)
`define BLCK_ENTRY_WIDTH 50     // IPV4_WIDTH + NODE_INDEX_WIDTH + BLCK_COVER_WIDTH
`define NODE_ENTRY_WIDTH 800    // BLCK_ENTRY_WIDTH * NUM_CHILDS
`define BITS_PER_STEP 4         // Must be 2's pows
`define LOG_BITS_PER_STEP 2     // log(BITS_PER_STEP)
`define MAX_STEPS 8
`define ADDR_JUMP 32'h10000000  // Assign to IPv4 and BITS_PER_STEP
`define ZERO_FILL 28'b0

/* ARP */
`define MAC_WIDTH 48
`define ARP_ITEM_NUM_WIDTH 3
`define ARP_ITEM_NUM 8
`define PORT_WIDTH 2