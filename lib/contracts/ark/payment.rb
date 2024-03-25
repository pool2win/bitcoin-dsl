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

run './lib/ark/setup.rb'

puts @alice.to_p2wpkh
puts @asp.to_p2wpkh

# ASP creates a pool tx, one output is a connector output
@asp_coinbase = spendable_coinbase_for @asp

# Alice creates forfeit transaction, signed only by Alice. This is where we introduce the _empty keyword
#
# _empty is replace by an empty signature in the witness stack, this is used to create partially signed txs
#
# _skip leaves the entry in the stack unchanged, this is used to add signatures to partially signed txs
@alice_forfeit_tx = transaction inputs: [
                                  {
                                    tx: @alice_boarding_tx, vout: 0, script_sig: 'multisig:alice,_empty'
                                  }
                                ],
                                outputs: [
                                  {
                                    descriptor: 'wpkh(@asp)',
                                    amount: 49.998.sats
                                  }
                                ]

log 'ASP now has a foreit transaction partially signed by Alice'

assert_not_mempool_accept @alice_forfeit_tx

# ASP now creates connectors and pool transaction

# @pool_transaction = transaction inputs: [
#                                   { tx: @asp_coinbase, vout: 0, script_sig: 'p2wpkh:asp' }
#                                 ],
#                                 outputs: [
#                                 ]
