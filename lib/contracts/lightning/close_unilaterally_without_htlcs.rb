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

# Alice broadcasts her commitment transaction unilaterally
broadcast @alice_commitment_tx
confirm transaction: @alice_commitment_tx, to: @alice

# Bob's commitment transaction can no longer be broadcast
assert_not_mempool_accept @bob_commitment_tx

# Alice sweeps her fund from the commitment output
@alice_sweep_tx = transaction inputs: [
                                { tx: @alice_commitment_tx,
                                  vout: 0,
                                  script_sig: 'sig:@alice ""',
                                  csv: @local_delay }
                              ],
                              outputs: [
                                { descriptor: 'wpkh(@alice)', amount: 49.998.sats }
                              ]

# Alice can't sweep until local_delay blocks have been generated
assert_not_mempool_accept @alice_sweep_tx

extend_chain num_blocks: @local_delay, to: @alice

# Now alice can sweep the output from commitment transaction
broadcast @alice_sweep_tx
confirm transaction: @alice_sweep_tx, to: @alice
