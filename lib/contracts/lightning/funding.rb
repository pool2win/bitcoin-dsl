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

run_script './setup.rb'

@local_funding_input_tx = spendable_coinbase_for @local
@remote_funding_input_tx = spendable_coinbase_for @remote

@channel_funding_tx = transaction inputs: [
                                    { tx: @local_funding_input_tx, vout: 0, script_sig: 'sig:wpkh(@local)' },
                                    { tx: @remote_funding_input_tx, vout: 0, script_sig: 'sig:wpkh(@remote)' }
                                  ],
                                  outputs: [
                                    {
                                      policy: 'thresh(2,pk(@local),pk(@remote))',
                                      amount: 99.999.sats
                                    }
                                  ]

broadcast @channel_funding_tx

confirm transaction: @channel_funding_tx, to: @local

log 'Funding transaction confirmed'
