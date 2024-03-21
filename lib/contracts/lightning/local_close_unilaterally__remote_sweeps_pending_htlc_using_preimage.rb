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

run_script './add_htlc.rb'

# Alice broadcasts her commitment transaction unilaterally
broadcast @alice_commitment_tx
confirm transaction: @alice_commitment_tx, to: @alice

# Bob sweeps the local output for Alice using the revocation key
@bob_sweep_alice_funds =
  transaction inputs: [
                { tx: @alice_commitment_tx,
                  vout: 0,
                  script_sig: 'sig:@alice_revocation_key_for_bob 0x01' }
              ],
              outputs: [
                { descriptor: 'wpkh(@bob)', amount: 49.898.sats }
              ]

# Bob sweeps the not yet settled HTLC using the revocation key
@bob_sweep_htlc_output_using_preimage =
  transaction inputs: [
                { tx: @alice_commitment_tx,
                  vout: 1,
                  script_sig: 'sig:@bob_htlc_key @payment_preimage' }
              ],
              outputs: [
                { descriptor: 'wpkh(@bob)', amount: 0.09.sats }
              ]

broadcast @bob_sweep_alice_funds
confirm transaction: @bob_sweep_alice_funds, to: @bob

broadcast @bob_sweep_htlc_output_using_preimage
confirm transaction: @bob_sweep_htlc_output_using_preimage, to: @bob
