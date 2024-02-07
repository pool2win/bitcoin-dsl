# frozen_string_literal: false

# Print getblockchaininfo result to verify node is up and running
pretty_print getblockchaininfo

# Generate new keys
alice = key :new
asp = key :new

# Get P2WPKH address for Alice and mine blocks paying the address
address = alice.to_p2wpkh
generatetoaddress num_blocks: 1, to: address

# Get and print the block to verify things are working
blockhash = getblockhash hash: 1
block = getblock hash: blockhash, verbosity: 2
pretty_print block

# Extract coinbase data to use as input in first spending transaction
coinbase_amount = get_value block: block, tx_index: 0, vout_index: 0
coinbase_txid = get_txid block: block, tx_index: 0
coinbase_script_pubkey = get_script_pubkey block: block, tx_index: 0, vout_index: 0

# Create transaction with Alice spending 49 BTC to herself
alice_boarding_tx = transaction inputs: [
                                  {
                                    txid: coinbase_txid,
                                    vout: 0,
                                    signature: {
                                      sighash: :all,
                                      signed_by: alice,
                                      script_pubkey: coinbase_script_pubkey,
                                      segwit_version: :witness_v0
                                    }
                                  }
                                ],
                                outputs: [
                                  {
                                    address: asp.to_p2wpkh,
                                    value: 49 * 1_000_000
                                  }
                                ],
                                version: 2

# Verify transaction is properly signed
verification_result = alice_boarding_tx.verify_input_sig(0, coinbase_script_pubkey, amount: coinbase_amount)
puts "Input signature verification: #{verification_result}"
