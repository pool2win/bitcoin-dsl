# frozen_string_literal: false

run './lib/ark/setup.rb'

# Extend chain to pass CSV timelock
extend_chain num_blocks: 100, to: @alice

assert_height 203

@spend_tx = spend inputs: [
                    { tx: @alice_boarding_tx,
                      vout: 0,
                      script_sig: 'p2wpkh:asp_timelock nulldummy nulldummy nulldummy',
                      csv: 10 }
                  ],
                  outputs: [
                    {
                      address: 'p2wpkh:asp',
                      amount: 49.998 * SATS
                    }
                  ]

broadcast transaction: @spend_tx
extend_chain to: @alice
assert_confirmed transaction: @spend_tx
