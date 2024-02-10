# frozen_string_literal: false

# Print new state of chain
assert_equal 0, getblockchaininfo['blocks'], 'The height is not correct at genesis'

# Generate new keys
@alice = key :new
@asp = key :new
@asp_timelock = key :new

# Seed alice with some coins
@alice_address = @alice.to_p2wpkh
generatetoaddress num_blocks: 1,
                  to: @alice_address

# Seed asp with some coins and make coinbase spendable
@asp_address = @alice.to_p2wpkh
generatetoaddress num_blocks: 101,
                  to: @asp_address

assert_equal 102, getblockchaininfo['blocks'], 'The height is not correct at genesis'

@coinbase_details = extract_txid_vout blockheight: 1,
                                      tx_index: 0,
                                      vout_index: 0

logger.info 'Creating alice boarding transaction'

# Create transaction with Alice spending 49 BTC to herself
@alice_boarding_tx = transaction inputs: [
                                   {
                                     txid: @coinbase_details.txid,
                                     vout: 0,
                                     signature: {
                                       sighash: :all,
                                       signed_by: @alice,
                                       script_pubkey: @coinbase_details.script_pubkey,
                                       segwit_version: :witness_v0,
                                       amount: @coinbase_details.amount
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

verify_signature transaction: @alice_boarding_tx,
                 index: 0,
                 script_pubkey: @coinbase_details.script_pubkey,
                 amount: @coinbase_details.amount

broadcast transaction: @alice_boarding_tx
confirm transaction: @alice_boarding_tx, to_address: @alice_address

logger.info 'Boarding transaction confirmed'

# @pool_transaction = transaction inputs: [
#                                   {
#                                   }
#                                 ],
#                                 outputs: [
#                                   {}
#                                 ],
#                                 version: 2
