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
@bob = key :new

# Mine block with coinbase policy
extend_chain policy: 'thresh(2,pk(@alice),pk(@bob))'

assert_height 1

@coinbase_with_policy = get_coinbase_at 1

# Make policy coinbase spendable by spending to p2wkh
extend_chain to: @alice, num_blocks: 100

assert_confirmations @coinbase_with_policy, confirmations: 101

# Spend the coinbase with policy
@spend_coinbase = transaction inputs: [
                                { tx: @coinbase_with_policy,
                                  vout: 0,
                                  script_sig: '"" sig:@alice sig:@bob' }
                              ],
                              outputs: [
                                {
                                  descriptor: 'wpkh(@alice)',
                                  amount: 49.998.sats
                                }
                              ]

broadcast @spend_coinbase
extend_chain to: @alice
assert_confirmations @spend_coinbase, confirmations: 1
