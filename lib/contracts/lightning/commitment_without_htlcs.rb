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

run_script './funding.rb'

@alice_commitment_tx = transaction inputs: [
                                     { tx: @channel_funding_tx, vout: 0, script_sig: 'sig:multi(_empty,@bob)' }
                                   ],
                                   outputs: [
                                     # local output for Alice
                                     { script: %(OP_IF @alice_revocation_key_for_bob
                                                 OP_ELSE @local_delay OP_CHECKSEQUENCEVERIFY OP_DROP @alice
                                                 OP_ENDIF OP_CHECKSIG),
                                       amount: 49.999.sats },
                                     # remote output for Bob
                                     { descriptor: 'wpkh(@bob)', amount: 49.999.sats }
                                   ]

@bob_commitment_tx = transaction inputs: [
                                   { tx: @channel_funding_tx, vout: 0, script_sig: 'sig:multi(@alice,_empty)' }
                                 ],
                                 outputs: [
                                   # local output for Bob
                                   { script: %(OP_IF @bob_revocation_key_for_alice
                                               OP_ELSE @local_delay OP_CHECKSEQUENCEVERIFY OP_DROP @bob
                                               OP_ENDIF OP_CHECKSIG),
                                     amount: 49.999.sats },
                                   # remote output for Alice
                                   { descriptor: 'wpkh(@alice)', amount: 49.999.sats }
                                 ]

# Can't broadcast these transactions until fully signed
assert_not_mempool_accept @alice_commitment_tx
assert_not_mempool_accept @bob_commitment_tx

# Alice and bob arrange to sign the commitment transactions
update_script_sig for_tx: @alice_commitment_tx, at_index: 0, with_script_sig: 'sig:multi(@alice,@bob)'
assert_mempool_accept @alice_commitment_tx

update_script_sig for_tx: @bob_commitment_tx, at_index: 0, with_script_sig: 'sig:multi(@alice,@bob)'
assert_mempool_accept @bob_commitment_tx
