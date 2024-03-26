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
end

state_transition :create_funding_tx do
  @funding_tx = transaction inputs: [
                              { tx: @alice_coinbase_tx, vout: 0, script_sig: 'sig:wpkh(@alice)', sighash: :all }
                            ],
                            outputs: [
                              {
                                policy: 'or(99@thresh(2,pk(@alice),pk(@asp)),and(older(10),pk(@asp_timelock)))',
                                amount: 49.999.sats
                              }
                            ]
end

state_transition :broadcast_funding_tx do
  broadcast @funding_tx
  extend_chain

  assert_confirmations @funding_tx, confirmations: 1

  # Extend chain so that ASP can spend some coinbases
  extend_chain num_blocks: 101, to: @asp
end

state_transition :create_redeem_tx do
  # Redeem transaction for Alice is only signed by ASP at this point
  @redeem_tx = transaction inputs: [
                             { tx: @funding_tx, vout: 0, script_sig: 'sig:@asp sig:_empty' }
                           ],
                           outputs: [
                             {
                               policy: 'or(99@thresh(2,pk(@alice),pk(@asp)),and(older(10),pk(@alice_timelock)))',
                               amount: 49.998.sats
                             }
                           ]
  assert_not_mempool_accept @redeem_tx
end

# ASP now sends the redeem transaction to Alice

# Alices sends a signed request to ASP for initiating a payment to Bob
# ASP creates a Redeem transaction for Bob
state_transition :initialize_payment_to_bob do
  @pool_tx = transaction inputs: [
                           { tx: @asp_payment_coinbase_tx, vout: 0, script_sig: 'sig:wpkh(@asp)' }
                         ],
                         outputs: [
                           {
                             policy: 'or(99@thresh(2,pk(@bob),pk(@asp)),and(older(10),pk(@asp_timelock)))',
                             amount: 49.997.sats
                           },
                           {
                             descriptor: 'wpkh(@asp)', # The connector output
                             amount: 0.001.sats
                           }
                         ]
  assert_mempool_accept @pool_tx

  @redeem_tx_for_bob = transaction inputs: [
                                     { tx: @pool_tx, vout: 0, script_sig: 'sig:@asp sig:_empty ""' }
                                   ],
                                   outputs: [
                                     {
                                       policy: 'or(99@thresh(2,pk(@bob),pk(@asp)),and(older(10),pk(@bob_timelock)))',
                                       amount: 49.996.sats
                                     }
                                   ]

  # pool_tx is not confirmed yet, so Bob's redeem tx can't be accepted
  assert_not_mempool_accept @redeem_tx_for_bob
end

state_transition :build_alice_forfeit_tx do
  @forfeit_tx = transaction inputs: [
                              # Only signed by Alice
                              { tx: @redeem_tx, vout: 0, script_sig: 'sig:_empty sig:@alice ""' },
                              # connector output from pool_tx
                              { tx: @pool_tx, vout: 1, script_sig: 'sig:wpkh(@asp)' }
                            ],
                            outputs: [
                              { descriptor: 'wpkh(@asp)', amount: 49.997.sats }
                            ]
  # Can't broadcast forfeit tx until redeem tx is confirmed
  assert_not_mempool_accept @forfeit_tx
end

state_transition :publish_pool_tx do
  broadcast @pool_tx
  confirm transaction: @pool_tx
end

state_transition :bob_redeems_coins do
  # Bob adds his signature to redeem tx
  update_script_sig for_tx: @redeem_tx_for_bob, at_index: 0, with_script_sig: 'sig:@asp sig:@bob ""'
  # Bob can redeem his coins
  assert_mempool_accept @redeem_tx_for_bob
  # Alice can no longer redeem her coins
  assert_not_mempool_accept @redeem_tx
end

state_transition :alice_redeems_coins_after_timeout do
  add_csv_to_transaction @redeem_tx, index: 0, csv: 10
  update_script_sig for_tx: @redeem_tx, at_index: 0, with_script_sig: 'sig:@asp sig:@alice ""'

  broadcast @redeem_tx
  confirm transaction: @redeem_tx

  @spend_alice_coins = transaction inputs: [
                                     { tx: @redeem_tx, vout: 0,
                                       script_sig: 'sig:@alice_timelock @alice_timelock 0x01',
                                       csv: 10 }
                                   ],
                                   outputs: [
                                     { descriptor: 'wpkh(@alice)', amount: 49.997.sats }
                                   ]

  extend_chain num_blocks: 10
  # Alice can now redeem her coins
  assert_mempool_accept @spend_alice_coins
end

# Publish pool transaction, paying Alice to Bob
run_transitions :setup,
                :create_funding_tx,
                :create_redeem_tx,
                :broadcast_funding_tx,
                :initialize_payment_to_bob,
                :build_alice_forfeit_tx,
                :publish_pool_tx,
                :bob_redeems_coins

node :reset

run_transitions :setup,
                :create_funding_tx,
                :create_redeem_tx,
                :broadcast_funding_tx,
                :initialize_payment_to_bob,
                :build_alice_forfeit_tx,
                :alice_redeems_coins_after_timeout
