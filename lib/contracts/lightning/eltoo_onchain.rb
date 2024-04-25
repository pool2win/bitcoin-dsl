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

@alice = key :new
@alice_update_key = key :new
@alice_settlement_key = key :new

@bob = key :new
@bob_update_key = key :new
@bob_settlement_key = key :new

@update_script = %(
OP_IF
        2 @alice_settlement_key @bob_settlement_key 2 OP_CHECKMULTISIGVERIFY 10 OP_CSV
OP_ELSE
        2 @alice_update_key @bob_update_key 2 OP_CHECKMULTISIGVERIFY 10 OP_CSV
OP_ENDIF
)

transition :setup do
  extend_chain to: @alice, num_blocks: 101
  @alice_funding_input_tx = spendable_coinbase_for @alice
end

transition :alice_creates_funding do
  @funding_tx = transaction inputs: [
                              {
                                tx: @alice_funding_input_tx,
                                vout: 0,
                                script_sig: 'sig:_skip'
                              }
                            ],
                            outputs: [
                              {
                                script: @update_script,
                                # descriptor: 'wsh(multi(2,@alice_settlement_key,@bob_settlement_key))',
                                amount: 49.999.sats
                              }
                            ]
  assert_not_mempool_accept @funding_tx
end

transition :bob_creates_settlement do
  # Bob signs a settlement transaction paying agreed amounts to Alice
  @settlement_tx = transaction inputs: [
                                 {
                                   tx: @funding_tx,
                                   vout: 0,
                                   script_sig: 'sig:multi(_empty,@bob_settlement_key) 0x01',
                                   csv: 10
                                 }
                               ],
                               outputs: [
                                 {
                                   descriptor: 'wpkh(@alice)',
                                   amount: 49.998.sats
                                 }
                               ]
end

transition :alice_broadcasts_funding_tx do
  # Alice signs the funding transaction and broadcasts it
  update_script_sig for_tx: @funding_tx, at_index: 0, with_script_sig: 'sig:wpkh(@alice)'
  broadcast @funding_tx
  confirm transaction: @funding_tx, to: @bob
end

transition :alice_signs_settlement do
  update_script_sig for_tx: @settlement_tx, at_index: 0,
                    with_script_sig: 'sig:multi(@alice_settlement_key,@bob_settlement_key) 0x01'
  extend_chain num_blocks: 10
  assert_mempool_accept @settlement_tx
end

transition :alice_broadcasts_settlement do
  broadcast @settlement_tx
  confirm transaction: @settlement_tx
end

run_transitions :setup,
                :alice_creates_funding,
                :bob_creates_settlement,
                :alice_broadcasts_funding_tx,
                :alice_signs_settlement,
                :alice_broadcasts_settlement
