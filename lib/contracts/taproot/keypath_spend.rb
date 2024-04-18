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
Bitcoin::Node::Configuration.new(network: :regtest)
@alice = key wif: 'cNtZwU6mYnUXDJtPqfyEaRsZuNy6C5PCZHY16xbps85HvRSn9KqE'
@bob = key wif: 'cMyDpdQkC1qRfWYNQHXawUwzEmXyFjv7PYw2EqYFRnhXhBs4bXt9'
@carol = key wif: 'cRCuYhzDcPPCjfVZPzSiuRAsXUgivChpz5xEfeXPRAi2EDnuHymz'

# Seed alice with some coins and make coinbase spendable
extend_chain num_blocks: 101, to: @alice

# Get coinbase to spend using tr
@coinbase_tx = get_coinbase_at 2

@taproot_keypath_tx = transaction inputs: [
                                    { tx: @coinbase_tx,
                                      vout: 0,
                                      script_sig: 'sig:wpkh(@alice)' }
                                  ],
                                  outputs: [
                                    {
                                      taproot: { internal_key: @bob }, # No script leaves
                                      amount: 49.999.sats
                                    }
                                  ]

broadcast @taproot_keypath_tx
confirm transaction: @taproot_keypath_tx

log 'Transaction with taproot output confirmed'

@bob_tweaked_private_key = taproot_tweak_private_key @bob

@spend_taproot_output_tx = transaction inputs: [
                                         { tx: @taproot_keypath_tx,
                                           vout: 0,
                                           script_sig: { keypath: @bob_tweaked_private_key }, # Spend using keypath
                                           sighash: :all }
                                       ],
                                       outputs: [
                                         { descriptor: 'wpkh(@carol)',
                                           amount: 49.998.sats }
                                       ]

assert_mempool_accept @spend_taproot_output_tx

broadcast @spend_taproot_output_tx
confirm transaction: @spend_taproot_output_tx

log 'Taproot keypath transaction spent'
