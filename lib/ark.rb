# frozen_string_literal: false

# Print new state of chain
assert_equal 0, getblockchaininfo['blocks'], 'The height is not correct at genesis'

# Generate new keys
@alice = key :new
@asp = key :new
@asp_timelock = key :new

# Seed alice with some coins
@alice_address = @alice.to_p2wpkh
generatetoaddress num_blocks: 1, to: @alice_address

# Seed asp with some coins and make coinbase spendable
@asp_address = @alice.to_p2wpkh
generatetoaddress num_blocks: 101, to: @asp_address

assert_equal 102, getblockchaininfo['blocks'], 'The height is not correct at genesis'

coinbase_amount, coinbase_txid, coinbase_script_pubkey = extract_output_details blockheight: 1,
                                                                                tx_index: 0,
                                                                                vout_index: 0

logger.info 'Creating alice boarding transaction'

# Create transaction with Alice spending 49 BTC to herself
@alice_boarding_tx = transaction inputs: [
                                   {
                                     txid: coinbase_txid,
                                     vout: 0,
                                     signature: {
                                       sighash: :all,
                                       signed_by: @alice,
                                       script_pubkey: coinbase_script_pubkey,
                                       segwit_version: :witness_v0
                                     }
                                   }
                                 ],
                                 outputs: [
                                   {
                                     policy: 'or(thresh(2,pk($alice),pk($asp)),and(older(5000),pk($asp_timelock)))',
                                     value: 49.999 * 100_000_000
                                   }
                                 ],
                                 version: 2

# Verify transaction is properly signed
verification_result = @alice_boarding_tx.verify_input_sig(0, coinbase_script_pubkey, amount: coinbase_amount)
assert verification_result, 'Transaction verifcation failed'

# Test mempool will accept alice boarding transaction
accepted = testmempoolaccept rawtxs: [@alice_boarding_tx.to_hex]
assert accepted[0]['allowed'], "Alice boarding tx not accepted #{accepted.inspect}"

# Broadcast alice boarding transaction
send_result = sendrawtransaction tx: @alice_boarding_tx.to_hex
assert_equal send_result, @alice_boarding_tx.txid, "Sending raw transaction failed. #{send_result}"

generatetoaddress num_blocks: 1, to: @alice.to_p2wpkh

assert_equal 103, getblockchaininfo['blocks'], 'The height is not correct after boarding transaction'

assert_confirmed txid: @alice_boarding_tx.txid, height: 103

logger.info 'Boarding transaction confirmed'

# @pool_transaction = transaction inputs: [
#                                   {
#                                   }
#                                 ],
#                                 outputs: [
#                                   {}
#                                 ],
#                                 version: 2
