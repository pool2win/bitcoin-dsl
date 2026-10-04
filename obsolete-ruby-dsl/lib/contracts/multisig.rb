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

# tag::setup[]
# Generate new keys
@alice = key :new
@bob = key :new
@carol = key :new

# Seed alice with some coins
extend_chain to: @alice

# Seed bob with some coins and make coinbase spendable
extend_chain num_blocks: 101, to: @bob

assert_equal get_height, 102, 'The height is not correct'

@coinbase_tx = get_coinbase_at 2
# end::setup[]

# tag::spend-coinbase[]
@multisig_tx = transaction inputs: [
                             { tx: @coinbase_tx,
                               vout: 0,
                               script_sig: 'sig:wpkh(@bob)' }
                           ],
                           outputs: [
                             { descriptor: 'wsh(multi(2,@alice,@bob))',
                               amount: 49.999.sats }
                           ]
broadcast @multisig_tx
confirm transaction: @multisig_tx, to: @alice
# end::spend-coinbase[]

# tag::spend-multisig[]
@spend_tx = transaction inputs: [
                          { tx: @multisig_tx,
                            vout: 0,
                            script_sig: 'sig:multi(@alice,@bob)' }
                        ],
                        outputs: [
                          { descriptor: 'wpkh(@carol)',
                            amount: 49.998.sats }
                        ]
broadcast @spend_tx
confirm transaction: @spend_tx, to: @alice
# end::spend-multisig[]

log 'Multisig transaction spent'
