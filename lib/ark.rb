# frozen_string_literal: false

# Print getblockchaininfo result to verify node is up and running
pretty_print getblockchaininfo

# Generate new keys
alice = key :new
asp = key :new

# Get P2WPKH address for Alice and mine blocks allowing coinbase spend
address = alice.to_p2wpkh
generatetoaddress num_blocks: 101, to: address

# Get the first block mined to alice
blockhash = getblockhash height: 1
block = getblock hash: blockhash, verbosity: 2
# pretty_print block

# Extract coinbase from first block for alice data to use as input in first spending transaction
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
                                    value: 49.999 * 100_000_000
                                  }
                                ],
                                version: 2

# Verify transaction is properly signed
verification_result = alice_boarding_tx.verify_input_sig(0, coinbase_script_pubkey, amount: coinbase_amount)
assert verification_result, 'Transaction verifcation failed'

accepted = testmempoolaccept rawtxs: [alice_boarding_tx.to_hex]
assert accepted[0]['allowed'], "Alice boarding tx not accepted #{accepted.inspect}"

send_result = sendrawtransaction tx: alice_boarding_tx.to_hex
assert_equal send_result, alice_boarding_tx.txid, "Sending raw transaction failed. #{send_result}"

generateblock to: alice.to_p2wpkh

pretty_print getblockchaininfo

query_result = getrawtransaction txid: alice_boarding_tx.txid
assert query_result, 'Transaction not found in a confirmed block'
