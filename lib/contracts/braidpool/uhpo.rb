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

@dummy_pool_key = key :new
@alice = key :new # 1/2 of block reward
@bob = key :new # 1/4 of block reward
@carol = key :new # 1/4 of block reward
@anon = key :new # Unknown party everyone spends to


# First 100 blocks, no coinbases are spendable, so no payout
# transaction exist yet
extend_chain num_blocks: 101, descriptor: 'wpkh(@dummy_pool_key)'

# In production, miners will build blocks with the payout
# transactions. We just send one to mempool in this script.

# The earliest spendable coinbase owned by the pool key. In this
# script, it is current height - 100
@coinbase_1 = get_coinbase_at 1
@apayout_setup = transaction inputs: [
                               { tx: @coinbase_1,
                                 vout: 0,
                                 script_sig: 'sig:wpkh(@dummy_pool_key)' }
                             ],
                             outputs: [
                               { amount: 24.999.sats, descriptor: 'wpkh(@alice)' },
                               { amount: 12.499.sats, descriptor: 'wpkh(@bob)' },
                               { amount: 12.499.sats, descriptor: 'wpkh(@carol)' }
                             ]
broadcast @payout_setup

# Step 1: Mine another block before any miner cashes out.

# Step 1.1: Confirm payout_setup
extend_chain descriptor: 'wpkh(@dummy_pool_key)'

# Step 2: Find second block
@coinbase_2 = get_coinbase_at 2

# Step 2.1: Create new payout update and confirm it
@payout_update_1 = transaction inputs: [
                                 { tx: @coinbase_2,
                                   vout: 0,
                                   script_sig: 'sig:wpkh(@dummy_pool_key)' },
                                 { tx: @payout_setup, vout: 0, sig: 'sig:wpkh(@alice)' },
                                 { tx: @payout_setup, vout: 1, sig: 'sig:wpkh(@bob)' },
                                 { tx: @payout_setup, vout: 2, sig: 'sig:wpkh(@carol)' }
                               ],
                               outputs: [
                                 { amount: (2 * 24.999).sats, descriptor: 'wpkh(@alice)' },
                                 { amount: (2 * 12.499).sats, descriptor: 'wpkh(@bob)' },
                                 { amount: (2 * 12.499).sats, descriptor: 'wpkh(@carol)' }
                               ]
broadcast @payout_update_1
confirm @payout_update_1

# Step 3: Alice cashes out some of her earnings. We create a new
# payout settlement and update
@alice_partial_cash_out = transaction inputs: [
                                        { tx: @payout_update_1, vout: 1, sig: 'sig:wpkh(@alice)'}
                                      ],
                                      outputs: [
                                        { amount: 10.sats, descriptor: 'wpkh(@anon)' }
                                      ]

@payout_update_1_prime = transaction inputs: [
                                       { tx: @payout_update_1, vout: 0, sig: 'sig:wpkh(@alice)' },
                                       { tx: @payout_update_1, vout: 1, sig: 'sig:wpkh(@bob)' },
                                       { tx: @payout_update_1, vout: 2, sig: 'sig:wpkh(@carol)' }
                                     ],
                                     outputs: [
                                       { amount: (2 * 24.999).sats, descriptor: 'wpkh(@alice)' },
                                       { amount: (2 * 12.499).sats, descriptor: 'wpkh(@bob)' },
                                       { amount: (2 * 12.499).sats, descriptor: 'wpkh(@carol)' }
                                     ]

# Step 3.1: Create a new update transaction to reflect Alice,
# checkout. To make this atomic, we need a connector output



# # Pay out miner_a
# @payout_alice = transaction inputs: [
#                               { tx: @coinbase,
#                                 vout: 0,
#                                 script_sig: 'sig:wpkh(@dummy_pool_key)' }
#                             ],
#                             outputs: [
#                               { amount: 25.sats, descriptor: 'wpkh(@alice)' },
#                               { amount: 12.5.sats, descriptor: 'wpkh(@bob)' },
#                               { amount: 12.5.sats, descriptor: 'wpkh(@carol)' }
#                             ]

# broadcast @spend_to
# confirm transaction: @spend_to
