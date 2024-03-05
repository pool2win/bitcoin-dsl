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

# A transaction A is said to be anchored to transaction B if A can
# only if spent if B has been spent.
#
# In this script we demonstrate how Bitcoin DSL\ is used to quickly
# define the anchor relationship between two (or more?) transactions.
#
# We construct two transactions, tx_a and tx_b, and then declare that
# tx_a is anchored to tx_b.

assert_height 0

# Generate new keys
@alice = key :new
@bob = key :new
@charlie = key :new

# Seed alice with some coins
extend_chain to: @alice

# Seed bob with some coins
extend_chain to: @bob

# Make both coinbases spendable
extend_chain num_blocks: 100

@alice_coinbase = spendable_coinbase_for @alice
@bob_coinbase = spendable_coinbase_for @bob

@alice_to_bob = transaction inputs: [
                              { tx: @alice_coinbase, vout: 0, script_sig: 'p2wpkh:alice' }
                            ],
                            outputs: [
                              { address: 'p2wpkh:bob', amount: 49.99.sats }
                            ]

@bob_to_charlie = transaction inputs: [
                                { tx: @bob_coinbase, vout: 0, script_sig: 'p2wpkh:bob' }
                              ],
                              outputs: [
                                { address: 'p2wpkh:charlie', amount: 49.99.sats }
                              ]

anchor transaction: @alice_to_bob, to: @bob_to_charlie, dust_for: @alice

assert_mempool_accept @bob_to_charlie
assert_not_mempool_accept @alice_to_bob

assert_mempool_accept @bob_to_charlie, @alice_to_bob

broadcast_multiple [@bob_to_charlie, @alice_to_bob]
