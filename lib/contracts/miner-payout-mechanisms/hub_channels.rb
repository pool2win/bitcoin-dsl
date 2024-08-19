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

@hub = key :new
@hub_alt = key :new
@hub_out1 = key :new
@hub_out2 = key :new

@miner1 = key :new
@miner1_revocation_key_for_hub = key :new
@hub_revocation_key_for_miner1 = key :new

@miner2 = key :new

@local_delay = 1008

@hub_preimage = 'hub preimage'
@hub_x = hash160(@hub_preimage)

transition :hub_setup do
  extend_chain descriptor: 'wpkh(@hub)'
  extend_chain num_blocks: 100

  @hub_tx = spendable_coinbase_for @hub
  @hub_split_tx = transaction inputs: [
                                { tx: @hub_tx, vout: 0, script_sig: 'sig:wpkh(@hub)' }
                              ],
                              outputs: [
                                { descriptor: 'wpkh(@hub_out1)', amount: 24.998.sats },
                                { descriptor: 'wpkh(@hub_out2)', amount: 24.998.sats }
                              ]

  broadcast @hub_split_tx
  confirm transaction: @hub_split_tx
end

transition :block_found_by_miner1 do
  extend_chain policy: 'or(thresh(2,pk(@hub),pk(@miner1)),and(pk(@hub_alt),hash160(@hub_x)))'
end

transition :create_funding_txs do
  @miner1_channel_tx = transaction inputs: [
                                     { tx: @hub_split_tx, vout: 0, script_sig: 'sig:wpkh(@hub_out1)' }
                                   ],
                                   outputs: [
                                     { descriptor: 'wsh(multi(2,@hub,@miner1))', amount: 24.997.sats }
                                   ]

  @miner2_channel_tx = transaction inputs: [
                                     { tx: @hub_split_tx, vout: 0, script_sig: 'sig:wpkh(@hub_out2)' }
                                   ],
                                   outputs: [
                                     { descriptor: 'wsh(multi(2,@hub,@miner2))', amount: 24.997.sats }
                                   ]
end

transition :create_miner1_commitment_txs do
  @miner1_commitment_for_hub = transaction inputs: [
                                             { tx: @miner1_channel_tx,
                                               vout: 0,
                                               script_sig: 'sig:multi(_empty,@miner1)' }
                                           ],
                                           outputs: [
                                             { script: %(OP_IF @miner1_revocation_key_for_hub
                                               OP_ELSE @local_delay OP_CHECKSEQUENCEVERIFY OP_DROP @hub
                                               OP_ENDIF OP_CHECKSIG),
                                               amount: 23.997.sats },
                                             { descriptor: 'wpkh(@miner1)',
                                               amount: 1.0.sats }
                                           ]

  @hub_commitment_for_miner1 = transaction inputs: [
                                             { tx: @miner1_channel_tx,
                                               vout: 0,
                                               script_sig: 'sig:multi(@hub,_empty)' }
                                           ],
                                           outputs: [
                                             { descriptor: 'wpkh(@hub)',
                                               amount: 23.997.sats },
                                             { script: %(OP_IF @hub_revocation_key_for_miner1
                                               OP_ELSE @local_delay OP_CHECKSEQUENCEVERIFY OP_DROP @miner1
                                               OP_ENDIF OP_CHECKSIG),
                                               amount: 1.0.sats }
                                           ]
end

transition :confirm_miner1_channel do
  broadcast @miner1_channel_tx
  confirm transaction: @miner1_channel_tx
end

run_transitions :hub_setup,
                :block_found_by_miner1,
                :create_funding_txs,
                :create_miner1_commitment_txs,
                :confirm_miner1_channel

# See close transitions in contracts/lightning directory to see how
# the commitment transaction can cooperatively or unilaterally close,
# and how older commitment transactions can be punished
