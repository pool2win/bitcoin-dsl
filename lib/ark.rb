# frozen_string_literal: false

# ARK script goals:
# 1. Alice onboards with an ASP
# 1.1 ASP is non-cooperative and Alice leaves after 1y with her coins
# 2. Alice makes off chain payment to Bob
# 3. Now multiple branches need to exploration:
# 3.0 ASP refuses to accept Alice's request to make payment
# 3.1 Alice cooperatively reverts and undoes off chain payment
# 3.2 Alice unilaterally reverts and undoes off chain payment
# 3.2 Bob cooperatively leaves the ARK with received payment
# 3.3 Bob unilaterally leaves the ARK with received payment

# Print new state of chain
assert_equal 0, getblockchaininfo['blocks'], 'The height is not correct at genesis'

# Generate new keys
@alice = key :new
@asp = key :new
@asp_timelock = key :new

# Seed alice with some coins
extend_chain to: @alice

# Seed asp with some coins and make coinbase spendable
extend_chain num_blocks: 101, to: @asp

assert_equal get_height, 102, 'The height is not correct'

coinbase_tx = get_coinbase_at 2

@alice_boarding_tx = spend inputs: [
                             { tx: coinbase_tx, vout: 0, script_sig: 'p2wpkh:asp', sighash: :all }
                           ],
                           outputs: [
                             {
                               policy: 'or(99@thresh(2,pk($alice),pk($asp)),and(older(5000),pk($asp_timelock)))',
                               amount: 49.999 * SATS
                             }
                           ]

verify_signature for_transaction: @alice_boarding_tx,
                 at_index: 0,
                 with_prevout: [coinbase_tx, 0]

broadcast transaction: @alice_boarding_tx
confirm transaction: @alice_boarding_tx, to: @alice
logger.info 'Boarding transaction confirmed'

pp @alice_boarding_tx.to_h

@spend_tx = spend inputs: [
                    { tx: @alice_boarding_tx, vout: 0, script_sig: 'multisig:alice,asp' }
                  ],
                  outputs: [
                    {
                      address: 'p2wpkh:asp',
                      amount: 49.998 * SATS
                    }
                  ]

pp @spend_tx.to_h

broadcast transaction: @spend_tx
confirm transaction: @spend_tx, to: @alice
logger.info 'Boarding transaction co-operatively spent'
