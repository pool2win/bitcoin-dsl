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

# tag::tweaked-keys[]
@alice = key :new
@bob = key :new

@tweak = 'beef' # <1>
@alice_tweaked_public_key = tweak_public_key @alice, with: @tweak # <1>
@alice_tweaked_private_key = tweak_private_key @alice, with: @tweak # <1>

extend_chain to: @alice_tweaked_public_key, num_blocks: 101

@coinbase_to_spend = spendable_coinbase_for @alice_tweaked_public_key # <2>

@to_bob = transaction inputs: [{ tx: @coinbase_to_spend,
                                 vout: 0,
                                 script_sig: 'sig:wpkh(@alice_tweaked_private_key)' }], # <3>
                      outputs: [{ amount: 49.999.sats, descriptor: 'wpkh(@bob)' }]

assert_mempool_accept @to_bob

broadcast @to_bob

confirm transaction: @to_bob

assert_output_is_spent transaction: @coinbase_to_spend, vout: 0
# end::tweaked-keys[]
