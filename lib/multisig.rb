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

# Print new state of chain
assert_equal 0, getblockchaininfo['blocks'], 'The height is not correct at genesis'

# Generate new keys
@alice = key :new
@bob = key :new

# Seed alice with some coins
extend_chain to: @alice

# Seed bob with some coins and make coinbase spendable
extend_chain num_blocks: 101, to: @bob

assert_equal get_height, 102, 'The height is not correct'

coinbase_tx = get_coinbase_at 2

@multisig_tx = transaction inputs: [
                             { tx: coinbase_tx, vout: 0, script_sig: 'p2wpkh:bob', sighash: :all }
                           ],
                           outputs: [
                             {
                               policy: 'thresh(2,pk($alice),pk($bob))',
                               amount: 49.999.sats
                             }
                           ]

verify_signature for_transaction: @multisig_tx,
                 at_index: 0,
                 with_prevout: [coinbase_tx, 0]

broadcast @multisig_tx

confirm transaction: @multisig_tx, to: @alice

logger.info 'Multisig transaction confirmed'

@spend_tx = transaction inputs: [
                          { tx: @multisig_tx, vout: 0, script_sig: 'multisig:alice,bob' }
                        ],
                        outputs: [
                          {
                            address: 'p2wpkh:bob',
                            amount: 49.998.sats
                          }
                        ]

broadcast @spend_tx
confirm transaction: @spend_tx, to: @alice

logger.info 'Multisig transaction spent'
