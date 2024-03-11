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
@alice = key :new

# Mine to an address with miniscript policy
extend_chain num_blocks: 1, policy: 'and(older(10),pk(@alice))'

# Load the coinbase with miniscript policy
@alice_coinbase_tx = get_coinbase_at 1

@csv_tx = transaction inputs: [
                        { tx: @alice_coinbase_tx,
                          vout: 0,
                          script_sig: 'sig:@alice',
                          csv: 10 }
                      ],
                      outputs: [
                        {
                          descriptor: wpkh(@alice),
                          amount: 49.998.sats
                        }
                      ]

assert_not_mempool_accept @csv_tx

# Mine blocks for CSV requirements and making coinbase spendable
extend_chain num_blocks: 100

assert_mempool_accept @csv_tx

broadcast @csv_tx
extend_chain to: @alice
assert_confirmations @csv_tx, confirmations: 1
