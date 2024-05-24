# Copyright 2024 Kulpreet Singh
#
# This file is part of Bitcoin-DSL
#
# Bitcoin-DSL is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Bitcoin-DSL is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Bitcoin-DSL. If not, see <https://www.gnu.org/licenses/>.

# frozen_string_literal: false

state_transition :setup do
  # Generate new keys
  @alice = key :new
  @alice_timelock = key :new
  @bob = key :new
  @bob_timelock = key :new

  @asp = key :new
  @asp_timelock = key :new

  # Seed alice with some coins
  extend_chain to: @alice

  # Seed asp with some coins and make coinbase spendable
  extend_chain num_blocks: 110, to: @asp

  @alice_coinbase_tx = spendable_coinbase_for @alice
  @asp_payment_coinbase_tx = get_coinbase_at 3

  # A timeout period it can be weeks or months, we use 10 blocks for now.
  @timeout_period = 10
end

# tag::create_funding_tx[]
state_transition :create_funding_tx do # <1>
  @funding_tx = transaction inputs: [
                              { tx: @alice_coinbase_tx, vout: 0, script_sig: 'sig:_empty' } # <2>
                            ],
                            outputs: [
                              {
                                policy: 'or(99@thresh(2,pk(@alice),pk(@asp)),'\
                                        'and(older(@timeout_period),pk(@asp_timelock)))', # <3>
                                amount: 49.999.sats
                              }
                            ]
  assert_not_mempool_accept @funding_tx # <4>
end
# end::create_funding_tx[]

# tag::create_redeem_tx[]
state_transition :create_redeem_tx do
  # Redeem transaction for Alice is only signed by ASP at this point
  @redeem_tx = transaction inputs: [
                             { tx: @funding_tx, vout: 0, script_sig: 'sig:@asp sig:_empty' } # <1>
                           ],
                           outputs: [
                             {
                               policy: 'or(thresh(2,pk(@alice),pk(@asp)),'\
                                       'and(older(@timeout_period),pk(@alice_timelock)))', # <2>
                               amount: 49.998.sats
                             }
                           ]
  assert_not_mempool_accept @redeem_tx # <3>
end
# end::create_redeem_tx[]

# tag::broadcast_funding_tx[]
state_transition :broadcast_funding_tx do
  update_script_sig for_tx: @funding_tx,
                    at_index: 0,
                    with_script_sig: 'sig:wpkh(@alice)' # <1>
  broadcast @funding_tx
  extend_chain
  assert_confirmations @funding_tx, confirmations: 1
  # Extend chain so that ASP can spend some coinbases
  extend_chain num_blocks: 101, to: @asp
end
# end::broadcast_funding_tx[]

# ASP now sends the redeem transaction to Alice

# tag::initialise_payment_to_bob[]
# Alice sends a signed request to ASP for initiating a payment to Bob
# ASP creates a Redeem transaction for Bob
state_transition :initialise_payment_to_bob do
  @pool_tx = transaction inputs: [
                           { tx: @asp_payment_coinbase_tx, vout: 0, script_sig: 'sig:wpkh(@asp)' }
                         ],
                         outputs: [
                           {
                             policy: 'or(99@thresh(2,pk(@bob),pk(@asp)),'\
                                     'and(older(@timeout_period),pk(@asp_timelock)))',
                             amount: 49.997.sats
                           },
                           {
                             descriptor: 'wpkh(@asp)', # The connector output # <1>
                             amount: 0.001.sats
                           }
                         ]
  assert_mempool_accept @pool_tx

  @redeem_tx_for_bob = transaction inputs: [
                                     { tx: @pool_tx, vout: 0, script_sig: 'sig:@asp sig:_empty ""' } # <2>
                                   ],
                                   outputs: [
                                     {
                                       policy: 'or(99@thresh(2,pk(@bob),pk(@asp)),'\
                                               'and(older(@timeout_period),pk(@bob_timelock)))', # <3>
                                       amount: 49.996.sats
                                     }
                                   ]

  # pool_tx is not confirmed yet, so Bob's redeem tx can't be accepted
  assert_not_mempool_accept @redeem_tx_for_bob
end
# end::initialise_payment_to_bob[]

# tag::build_alice_forfeit_tx[]
state_transition :build_alice_forfeit_tx do
  @forfeit_tx = transaction inputs: [
                              # Only signed by Alice
                              { tx: @redeem_tx, vout: 0, script_sig: 'sig:_empty sig:@alice ""' }, # <1>
                              # connector output from pool_tx
                              { tx: @pool_tx, vout: 1, script_sig: 'sig:wpkh(@asp)' } # <2>
                            ],
                            outputs: [
                              { descriptor: 'wpkh(@asp)', amount: 49.997.sats }
                            ]
  # Can't broadcast forfeit tx until redeem tx is confirmed
  assert_not_mempool_accept @forfeit_tx
end
# end::build_alice_forfeit_tx[]

# tag::publish_pool_tx[]
state_transition :publish_pool_tx do
  broadcast @pool_tx
  confirm transaction: @pool_tx
end
# end::publish_pool_tx[]

# tag::bob_redeems_coins[]
state_transition :bob_redeems_coins do
  # Bob adds his signature to redeem tx
  update_script_sig for_tx: @redeem_tx_for_bob,
                    at_index: 0,
                    with_script_sig: '"" sig:@bob sig:@asp' # <1>
  # Bob can redeem his coins
  assert_mempool_accept @redeem_tx_for_bob
  # Alice can no longer redeem her coins
  assert_not_mempool_accept @redeem_tx
end
# end::bob_redeems_coins[]

# tag::alice_redeems_coins_after_timeout[]
state_transition :alice_redeems_coins_after_timeout do
  add_csv_to_transaction @redeem_tx, index: 0, csv: @timeout_period
  update_script_sig for_tx: @redeem_tx,
                    at_index: 0,
                    with_script_sig: '"" sig:@alice sig:@asp' # <1>

  broadcast @redeem_tx
  confirm transaction: @redeem_tx

  @spend_alice_coins = transaction inputs: [
                                     { tx: @redeem_tx, vout: 0,
                                       script_sig: 'sig:@alice_timelock', # <2>
                                       csv: @timeout_period }
                                   ],
                                   outputs: [
                                     { descriptor: 'wpkh(@alice)', amount: 49.997.sats }
                                   ]

  extend_chain num_blocks: @timeout_period # <3>
  # Alice can now redeem her coins
  assert_mempool_accept @spend_alice_coins
end
# end::alice_redeems_coins_after_timeout[]

# tag::pay_alice_to_bob[]
# Publish pool transaction, paying Alice to Bob
run_transitions :setup,
                :create_funding_tx,
                :create_redeem_tx,
                :broadcast_funding_tx,
                :initialise_payment_to_bob,
                :build_alice_forfeit_tx,
                :publish_pool_tx, # <1>
                :bob_redeems_coins
# end::pay_alice_to_bob[]

# tag::reset[]
node :reset
# end::reset[]

# tag::cancelled_payment[]
# Cancel the payment because ASP is not responsive
run_transitions :setup,
                :create_funding_tx,
                :create_redeem_tx,
                :broadcast_funding_tx,
                :initialise_payment_to_bob,
                :build_alice_forfeit_tx,
                :alice_redeems_coins_after_timeout # <1>
# end::cancelled_payment[]
