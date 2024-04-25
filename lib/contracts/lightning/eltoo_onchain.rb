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
@alice_settlement_key = key :new

@bob = key :new
@bob_settlement_key = key :new

@update_script = %(
OP_IF
        2 @alice_settlement_key @bob_settlement_key 2 OP_CHECKMULTISIGVERIFY 10 OP_CSV
OP_ELSE
        2 @alice @bob 2 OP_CHECKMULTISIG
OP_ENDIF
)

transition :setup do
  extend_chain to: @alice, num_blocks: 101
  @alice_input_tx = spendable_coinbase_for @alice

  @setup_tx = transaction inputs: [{ tx: @alice_input_tx, vout: 0, script_sig: 'sig:_skip' }],
                          outputs: [{ script: @update_script, amount: 49.999.sats }]
  assert_not_mempool_accept @setup_tx
end

transition :bob_creates_settlement do
  @settlement_tx = transaction inputs: [{ tx: @setup_tx,
                                          vout: 0,
                                          script_sig: 'sig:multi(_empty,@bob_settlement_key) 0x01',
                                          csv: 10 }],
                               outputs: [{ descriptor: 'wpkh(@alice)',
                                           amount: 49.998.sats }]
end

transition :alice_broadcasts_setup_tx do
  # Alice signs the funding transaction and broadcasts it
  update_script_sig for_tx: @setup_tx, at_index: 0, with_script_sig: 'sig:wpkh(@alice)'
  broadcast @setup_tx
  confirm transaction: @setup_tx, to: @bob
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

transition :create_new_update do
  # new update transaction spending setup tx
  @update_tx = transaction inputs: [{ tx: @setup_tx, vout: 0, script_sig: 'sig:multi(@alice,@bob) ""' }],
                           outputs: [{ script: @update_script, amount: 49.998.sats }]
  assert_mempool_accept @update_tx
end

transition :broadcast_new_update do
  broadcast @update_tx
  confirm transaction: @update_tx
end

transition :create_new_settlement do
  # new settlement transaction spending update tx
  @new_settlement_tx = transaction inputs: [{ tx: @update_tx, vout: 0,
                                              script_sig: 'sig:multi(_empty,@bob_settlement_key) 0x01', csv: 10 }],
                                   outputs: [{ descriptor: 'wpkh(@alice)', amount: 48.997.sats },
                                             { descriptor: 'wpkh(@bob)', amount: 1.sats }]
  assert_not_mempool_accept @new_settlement_tx
end

transition :broadcast_new_settlement do
  update_script_sig for_tx: @new_settlement_tx, at_index: 0,
                    with_script_sig: 'sig:multi(@alice_settlement_key,@bob_settlement_key) 0x01'
  extend_chain num_blocks: 10
  broadcast @new_settlement_tx
  confirm transaction: @new_settlement_tx
end

transition :broadcast_new_settlement_fails do
  update_script_sig for_tx: @new_settlement_tx, at_index: 0,
                    with_script_sig: 'sig:multi(@alice_settlement_key,@bob_settlement_key) 0x01'
  extend_chain num_blocks: 10
  assert_not_mempool_accept @new_settlement_tx
end

# Simple case: settlement immediately spends from setup
run_transitions :setup,
                :bob_creates_settlement,
                :alice_broadcasts_setup_tx,
                :alice_signs_settlement,
                :alice_broadcasts_settlement

# Create an update and a new settlement, and finally spend the settlement.
# In this case, the setup is spent by an update which is spent by the settlement.
run_transitions :reset,
                :setup,
                :bob_creates_settlement,
                :alice_broadcasts_setup_tx,
                :create_new_update,
                :create_new_settlement,
                :broadcast_new_update,
                :broadcast_new_settlement

# Capture the case where a settlement fails to be spent before the
# update has confirmed
run_transitions :reset,
                :setup,
                :bob_creates_settlement,
                :alice_broadcasts_setup_tx,
                :create_new_update,
                :create_new_settlement,
                :broadcast_new_settlement_fails
