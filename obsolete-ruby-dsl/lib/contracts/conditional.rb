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

extend_chain to: @alice, num_blocks: 101

@input_tx = spendable_coinbase_for @alice

@conditional_output_script = %(
OP_IF
        @alice OP_CHECKSIGVERIFY 10 OP_CSV
OP_ELSE
        @bob OP_CHECKSIGVERIFY 10 OP_CSV
OP_ENDIF
)

@generate_conditional_output = transaction inputs: [
                                             {
                                               tx: @input_tx,
                                               vout: 0,
                                               script_sig: 'sig:wpkh(@alice)'
                                             }
                                           ],
                                           outputs: [
                                             {
                                               script: @conditional_output_script,
                                               amount: 49.999.sats
                                             }
                                           ]
@spending_tx = transaction inputs: [
                             {
                               tx: @generate_conditional_output,
                               vout: 0,
                               script_sig: 'sig:@alice 0x01',
                               csv: 10
                             }
                           ],
                           outputs: [
                             {
                               descriptor: 'wpkh(@alice)',
                               amount: 49.998.sats
                             }
                           ]

broadcast @generate_conditional_output
confirm transaction: @generate_conditional_output, to: @bob

assert_not_mempool_accept @spending_tx
extend_chain num_blocks: 10
assert_mempool_accept @spending_tx
