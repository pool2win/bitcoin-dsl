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

# Generate keys for channel funding tx
@alice = key :new
@alice_revocation_key_for_bob = key :new
@alice_htlc_key = key :new

@bob = key :new
@bob_revocation_key_for_alice = key :new
@bob_htlc_key = key :new

@local_delay = 1008

# 32 byte preimage in hex
@payment_preimage = 'beef' * 16

# Seed alice with some coins
extend_chain to: @alice

# Seed bob with some coins and make coinbase spendable
extend_chain num_blocks: 101, to: @bob
