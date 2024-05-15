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

# Mine block with coinbase descriptor
extend_chain descriptor: 'wpkh(@alice)'

assert_height 1

@coinbase_with_descriptor = get_coinbase_at 1

# Make descriptor coinbase spendable by spending to p2wkh
extend_chain to: @alice, num_blocks: 100

assert_confirmations @coinbase_with_descriptor, confirmations: 100
