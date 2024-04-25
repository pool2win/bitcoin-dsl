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

# Generate new keys
@alice = key wif: 'cNtZwU6mYnUXDJtPqfyEaRsZuNy6C5PCZHY16xbps85HvRSn9KqE'
@bob = key wif: 'cMyDpdQkC1qRfWYNQHXawUwzEmXyFjv7PYw2EqYFRnhXhBs4bXt9'
@carol = key wif: 'cRCuYhzDcPPCjfVZPzSiuRAsXUgivChpz5xEfeXPRAi2EDnuHymz'

# tag::create_taproot_input[]
transition :create_input_tx do
  # Seed alice with some coins and make coinbase spendable
  extend_chain num_blocks: 101, to: @alice

  # Get coinbase to spend using tr
  @coinbase_tx = get_coinbase_at 2

  # tag::taproot_tx[]
  @taproot_output_tx = transaction inputs: [
                                     { tx: @coinbase_tx,
                                       vout: 0,
                                       script_sig: 'sig:wpkh(@alice)' }
                                   ],
                                   outputs: [
                                     {
                                       taproot: { internal_key: @bob, # <1>
                                                  leaves: ['pk(@carol)', 'pk(@alice)'] }, # <2>
                                       amount: 49.999.sats
                                     }
                                   ]
  # end::taproot_tx[]

  broadcast @taproot_output_tx
  confirm transaction: @taproot_output_tx

  log 'Transaction with taproot output confirmed'
end
# end::create_taproot_input[]

# tag::spend_via_scriptpath[]
transition :spend_first_leaf do
  @spend_taproot_output_tx = transaction inputs: [
                                           { tx: @taproot_output_tx,
                                             vout: 0,
                                             script_sig: { leaf_index: 0, # <1>
                                                           sig: 'sig:@carol' }, # <2>
                                             sighash: :all }
                                         ],
                                         outputs: [
                                           { descriptor: 'wpkh(@carol)',
                                             amount: 49.998.sats }
                                         ]
  broadcast @spend_taproot_output_tx
  confirm transaction: @spend_taproot_output_tx
  log 'Taproot script path transaction spent using first leaf'
end
# end::spend_via_scriptpath[]

transition :spend_second_leaf do
  @spend_taproot_output_tx = transaction inputs: [
                                           { tx: @taproot_output_tx,
                                             vout: 0,
                                             script_sig: { leaf_index: 1, sig: 'sig:@alice' },
                                             sighash: :all }
                                         ],
                                         outputs: [
                                           { descriptor: 'wpkh(@carol)',
                                             amount: 49.998.sats }
                                         ]

  broadcast @spend_taproot_output_tx
  confirm transaction: @spend_taproot_output_tx
  log 'Taproot script path transaction spent using second leaf'
end

# tag::spend_via_keypath[]
transition :spend_using_internal_key do
  @spend_taproot_output_tx = transaction inputs: [
                                           { tx: @taproot_output_tx,
                                             vout: 0,
                                             script_sig: { keypath: @bob }, # <1>
                                             sighash: :all }
                                         ],
                                         outputs: [
                                           { descriptor: 'wpkh(@carol)',
                                             amount: 49.998.sats }
                                         ]
  broadcast @spend_taproot_output_tx
  confirm transaction: @spend_taproot_output_tx
  log 'Taproot output spent using keypath'
end
# end::spend_via_keypath[]

run_transitions :create_input_tx, :spend_first_leaf
run_transitions :reset, :create_input_tx, :spend_second_leaf
run_transitions :reset, :create_input_tx, :spend_using_internal_key
