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

# ARK script goals:
# 1. Alice onboards with an ASP
# 1.1 ASP is non-cooperative and Alice leaves after 1y with her coins
# 2. Alice makes off chain payment to Bob
# 3. Now multiple branches need to exploration:
# 3.0 ASP refuses to accept Alice's request to make payment
# 3.1 Alice cooperatively reverts and undoes off chain payment
# 3.2 Alice unilaterally reverts and undoes off chain payment
# 3.2 Bob cooperatively leaves the ARK with received payment
# 3.3 Bob unilaterally leaves the ARK with received payment

assert_height 0

# Generate new keys
@alice = key :new
@asp = key :new
@asp_timelock = key :new

# Seed alice with some coins
extend_chain to: @alice

# Seed asp with some coins and make coinbase spendable
extend_chain num_blocks: 101, to: @asp

assert_height 102

coinbase_tx = get_coinbase_at 2

@alice_boarding_tx = transaction inputs: [
                                   { tx: coinbase_tx, vout: 0, script_sig: 'p2wpkh:asp', sighash: :all }
                                 ],
                                 outputs: [
                                   {
                                     policy: 'or(99@thresh(2,pk($alice),pk($asp)),and(older(10),pk($asp_timelock)))',
                                     amount: 49.999.sats
                                   }
                                 ]

verify_signature for_transaction: @alice_boarding_tx,
                 at_index: 0,
                 with_prevout: [coinbase_tx, 0]

broadcast @alice_boarding_tx
extend_chain to: @alice

assert_confirmed transaction: @alice_boarding_tx

# Extend chain so that ASP can spend some coinbases
extend_chain num_blocks: 101, to: @asp

assert_height 204
