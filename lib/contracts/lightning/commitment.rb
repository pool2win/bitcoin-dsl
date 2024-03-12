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

@to_local = 'OP_IF @remote_revocation_key OP_ELSE @local_delay OP_CHECKSEQUENCEVERIFY OP_DROP @local_revocation_key OP_ENDIF OP_CHECKSIG'

@to_remote = '@remote_revocation_key OP_CHECKSIGVERIFY 1 OP_CHECKSEQUENCEVERIFY'

@local_commitment_tx = transaction inputs: [
                                     { tx: @channel_funding_tx, vout: 0, script_sig: 'sig:multi(@local,_empty)' }
                                   ],
                                   outputs: [
                                     {
                                       script: @to_local,
                                       amount: 49.999.sats
                                     },
                                     {
                                       script: @to_remote,
                                       amount: 49.999.sats
                                     }
                                   ]

# Can't broadcast this transaction until fully signed
assert_not_mempool_accept @local_commitment_tx

update_script_sig for_tx: @local_commitment_tx, at_index: 0, with_script_sig: 'sig:multi(@local,@remote)'

assert_mempool_accept @local_commitment_tx

broadcast @local_commitment_tx
