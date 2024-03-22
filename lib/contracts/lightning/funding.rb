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

# tag::funding[]
run_script './setup.rb'

@alice_funding_input_tx = spendable_coinbase_for @alice
@bob_funding_input_tx = spendable_coinbase_for @bob

@channel_funding_tx = transaction inputs: [
                                    { tx: @alice_funding_input_tx,
                                      vout: 0,
                                      script_sig: 'sig:wpkh(@alice)' }, # <1>
                                    { tx: @bob_funding_input_tx,
                                      vout: 0,
                                      script_sig: 'sig:wpkh(@bob)' } # <1>
                                  ],
                                  outputs: [
                                    {
                                      descriptor: 'wsh(multi(2,@alice,@bob))', # <2>
                                      amount: 99.999.sats
                                    }
                                  ]

broadcast @channel_funding_tx

confirm transaction: @channel_funding_tx, to: @alice

log 'Funding transaction confirmed'
# end::funding[]
