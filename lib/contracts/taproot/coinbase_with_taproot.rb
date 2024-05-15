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
@carol = key :new

# tag::coinbase[]
# Mine block with taproot coinbase
extend_chain taproot: { internal_key: @bob, # <1>
                        leaves: ['pk(@carol)', 'pk(@alice)'] }
# end::coinbase[]

assert_height 1

@coinbase_with_taproot = get_coinbase_at 1

# Make coinbase spendable by spending to p2wkh
extend_chain to: @alice, num_blocks: 100

@spend_taproot_coinbase = transaction inputs: [
                                        { tx: @coinbase_with_taproot,
                                          vout: 0,
                                          script_sig: { keypath: @bob },
                                          sighash: :all }
                                      ],
                                      outputs: [
                                        { descriptor: 'wpkh(@carol)',
                                          amount: 49.998.sats }
                                      ]

broadcast @spend_taproot_coinbase
confirm transaction: @spend_taproot_coinbase
