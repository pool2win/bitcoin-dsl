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

# Extend chain to 101, so Alice has a spendable coinbase
extend_chain to: @alice, num_blocks: 101

assert_height 101
@coinbase = spendable_coinbase_for @alice
assert_not_nil @coinbase

# Reorg by height
reorg_chain height: 95
assert_height 95

# Alice has no spendable coinbases anymore
@coinbase = spendable_coinbase_for @alice
assert_nil @coinbase

extend_chain num_blocks: 10

@blockhash = getblockhash height: 95

# Reorg by blockhash
reorg_chain blockhash: @blockhash
assert_height 95

@coinbase = spendable_coinbase_for @alice
assert_nil @coinbase

extend_chain num_blocks: 10

# Reorg by transaction
@reorg_to_tx = get_coinbase_at 98
reorg_chain unconfirm_tx: @reorg_to_tx
assert_height 98

@coinbase = spendable_coinbase_for @alice
assert_nil @coinbase
