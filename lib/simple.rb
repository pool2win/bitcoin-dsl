@alice = key :new

# Mine 100 blocks, all with coinbase to alice.
extend_chain to: @alice, num_blocks: 101
