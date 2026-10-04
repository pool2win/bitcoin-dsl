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

# Folds a list of transactions into a tree that can be used in ARK
# like protocols

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

log "Alice coinbase #{@alice_coinbase[:txid]}"

num_outputs = 10

# Spend Alice coinbase to generate identical outputs
@multiple_vouts = transaction inputs: [
                                { tx: @alice_coinbase, vout: 0, script_sig: 'sig:wpkh(@alice)' }
                              ],
                              outputs: [
                                { descriptor: 'wpkh(@bob)', amount: 1.sats }
                              ] * num_outputs + [
                                { descriptor: 'wpkh(@bob)', amount: (49.99 - num_outputs).sats }
                              ]

# Confirm multiple vouts tx
broadcast @multiple_vouts
extend_chain num_blocks: 100

log 'Transaction with multiple vouts now confirmed'

@transactions_to_fold = transactions [
  {
    inputs: [
      { tx: @multiple_vouts, vout: 0, script_sig: 'sig:wpkh(@bob)' }
    ],
    outputs: [
      { descriptor: 'wpkh(@charlie)', amount: 0.99.sats }
    ]
  },
  {
    inputs: [
      { tx: @multiple_vouts, vout: 1, script_sig: 'sig:wpkh(@bob)' }
    ],
    outputs: [
      { descriptor: 'wpkh(@charlie)', amount: 0.99.sats }
    ]
  },
  {
    inputs: [
      { tx: @multiple_vouts, vout: 2, script_sig: 'sig:wpkh(@bob)' }
    ],
    outputs: [
      { descriptor: 'wpkh(@charlie)', amount: 0.99.sats }
    ]
  }
]

# verify_signature for_transaction: t, at_index: 0, with_prevout: [@multiple_vouts, 1]

broadcast_multiple @transactions_to_fold

log 'Multiple transactions sent'
