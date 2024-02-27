# frozen_string_literal: false

run './lib/ark/setup.rb'

@spend_tx = transaction inputs: [
                          { tx: @alice_boarding_tx, vout: 0, script_sig: 'multisig:alice,asp' }
                        ],
                        outputs: [
                          {
                            address: 'p2wpkh:asp',
                            amount: 49.998.sats
                          }
                        ]

broadcast transaction: @spend_tx
extend_chain to: @alice

assert_confirmed transaction: @spend_tx
