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

@alice_local = 'OP_IF @bob_revocation_key OP_ELSE @local_delay OP_CHECKSEQUENCEVERIFY OP_DROP @alice_revocation_key OP_ENDIF OP_CHECKSIG'
@alice_remote = '@bob_revocation_key OP_CHECKSIGVERIFY 1 OP_CHECKSEQUENCEVERIFY'

@bob_local = 'OP_IF @alice_revocation_key OP_ELSE @local_delay OP_CHECKSEQUENCEVERIFY OP_DROP @bob_revocation_key OP_ENDIF OP_CHECKSIG'
@bob_remote = '@alice_revocation_key OP_CHECKSIGVERIFY 1 OP_CHECKSEQUENCEVERIFY'

@alice_commitment_tx = transaction inputs: [
                                     { tx: @channel_funding_tx, vout: 0, script_sig: 'sig:multi(@alice,_empty)' }
                                   ],
                                   outputs: [
                                     {
                                       script: @alice_local,
                                       amount: 49.999.sats
                                     },
                                     {
                                       script: @alice_remote,
                                       amount: 49.999.sats
                                     }
                                   ]

@bob_commitment_tx = transaction inputs: [
                                   { tx: @channel_funding_tx, vout: 0, script_sig: 'sig:multi(_empty,@bob)' }
                                 ],
                                 outputs: [
                                   {
                                     script: @bob_local,
                                     amount: 49.999.sats
                                   },
                                   {
                                     script: @bob_remote,
                                     amount: 49.999.sats
                                   }
                                 ]

# Can't broadcast these transactions until fully signed
assert_not_mempool_accept @alice_commitment_tx
assert_not_mempool_accept @bob_commitment_tx

update_script_sig for_tx: @alice_commitment_tx, at_index: 0, with_script_sig: 'sig:multi(@alice,@bob)'
update_script_sig for_tx: @bob_commitment_tx, at_index: 0, with_script_sig: 'sig:multi(@alice,@bob)'

assert_mempool_accept @alice_commitment_tx
assert_mempool_accept @bob_commitment_tx
