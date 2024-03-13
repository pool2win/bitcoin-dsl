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

run_script './commitment.rb'

update_script_sig for_tx: @alice_commitment_tx, at_index: 0, with_script_sig: 'sig:multi(@alice,@bob)'

assert_mempool_accept @alice_commitment_tx
assert_not_mempool_accept @bob_commitment_tx

broadcast @alice_commitment_tx

confirm transaction: @alice_commitment_tx, to: @alice
