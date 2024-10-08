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
@miner2 = key :new

@hub_preimage = 'beef' * 16
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

transition :miner1_finds_block do
  extend_chain policy: 'or(99@thresh(2,pk(@hub),pk(@miner1)),and(pk(@hub_alt),hash160(@hub_x)))'
  @pool_coinbase = coinbase_at_tip
end

transition :make_coinbase_spendable do
  extend_chain num_blocks: 100
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

transition :create_miner1_commitment_tx do
  # Partially signed by hub and sent to miner1
  @commitment_for_miner1 = transaction inputs: [
                                         { tx: @miner1_channel_tx,
                                           vout: 0,
                                           script_sig: 'sig:multi(@hub,_empty)' }
                                       ],
                                       outputs: [
                                         { descriptor: 'wpkh(@hub)',
                                           amount: 23.996.sats },
                                         { policy: 'and(hash160(@hub_x),pk(@miner1))',
                                           amount: 1.0.sats }
                                       ]
end

# This payout commitment is signed by hub and sent to miner, so the
# miner has control over their coins. As pool finds more blocks, the
# new payout commitments will have a higher balance, so the miner has
# no incentive to broadcast an older commitment. Therefore, we don't
# need a revocation for these commitments.
transition :create_miner1_payout_commitment do
  @payout_miner1 = transaction inputs: [
                                 { tx: @miner1_channel_tx,
                                   vout: 0,
                                   script_sig: 'sig:multi(@hub,_empty)' }
                               ],
                               outputs: [
                                 { descriptor: 'wpkh(@hub)',
                                   amount: 22.996.sats },
                                 { descriptor: 'wpkh(@miner1)',
                                   amount: 2.0.sats }
                               ]
end

transition :create_miner1_second_commitment_tx do
  # Partially signed by hub and sent to miner1
  @second_commitment_for_miner1 = transaction inputs: [
                                                { tx: @miner1_channel_tx,
                                                  vout: 0,
                                                  script_sig: 'sig:multi(@hub,_empty)' }
                                              ],
                                              outputs: [
                                                { descriptor: 'wpkh(@hub)',
                                                  amount: 21.996.sats },
                                                { policy: 'and(hash160(@hub_x),pk(@miner1))',
                                                  amount: 3.0.sats }
                                              ]
end

transition :confirm_miner1_channel do
  broadcast @miner1_channel_tx
  confirm transaction: @miner1_channel_tx
end

transition :cooperative_spend_pool_coinbase do
  # Ideally, we also show a new commitment is created before the coop
  # spend to pool. We leave it out for now for brevity.
  @coop_spend_to_hub = transaction inputs: [
                                     { tx: @pool_coinbase, vout: 0, script_sig: 'sig:multi(@hub,@miner1)' }
                                   ],
                                   outputs: [
                                     { descriptor: 'wpkh(@hub)', amount: 49.998.sats }
                                   ]

  broadcast @coop_spend_to_hub
  confirm transaction: @coop_spend_to_hub

  # Miner broadcasts commitment to close channel and can claim coins after timeout.
  update_script_sig for_tx: @payout_miner1, at_index: 0, with_script_sig: 'sig:multi(@hub,@miner1)'
  broadcast @payout_miner1
  confirm transaction: @payout_miner1
end

transition :hub_spends_revealing_preimage do
  @non_coop_spend_by_hub = transaction inputs: [
                                         { tx: @pool_coinbase,
                                           vout: 0,
                                           script_sig: "@hub_preimage sig:wpkh(@hub_alt) '' '' ''" }
                                       ],
                                       outputs: [
                                         { descriptor: 'wpkh(@hub)', amount: 49.998.sats }
                                       ]
  broadcast @non_coop_spend_by_hub
  confirm transaction: @non_coop_spend_by_hub

  # # Miner can claim the @payout_miner1 commitment, but the amount in
  # # the new commitment is higher, so the miner claims that instead.
  # #
  # # Miner now knows the preimage and therefore can claim their coins as well

  # First broadcast commitment
  update_script_sig for_tx: @second_commitment_for_miner1, at_index: 0, with_script_sig: 'sig:multi(@hub,@miner1)'
  broadcast @second_commitment_for_miner1
  confirm transaction: @second_commitment_for_miner1

  # Then spend the commitment output
  @miner_claim_coins = transaction inputs: [
                                     { tx: @second_commitment_for_miner1,
                                       vout: 1,
                                       script_sig: '@hub_preimage sig:@miner1' }
                                   ],
                                   outputs: [
                                     { descriptor: 'wpkh(@miner1)', amount: 2.999.sats }
                                   ]
  broadcast @miner_claim_coins
  confirm transaction: @miner_claim_coins
end

# The Belcher specification requires that as a block is found, the hub
# updates the miner1 channel with new commitments and then the miner1
# can sign the coinbase to release the rewards for the hub.
#
# We don't show the hub - miner interaction here, but simply show how
# the coinbase is spent and then now the miner can claim coins.
#
# To see how the DSL help with revoking commitments, see the scripts
# under contracts/lightning directory.

run_transitions :hub_setup,
                :create_funding_txs,
                :create_miner1_commitment_tx,
                :confirm_miner1_channel,
                :miner1_finds_block,
                :make_coinbase_spendable,
                :create_miner1_payout_commitment,
                :cooperative_spend_pool_coinbase

run_transitions :reset,
                :hub_setup,
                :create_funding_txs,
                :create_miner1_commitment_tx,
                :confirm_miner1_channel,
                :miner1_finds_block,
                :make_coinbase_spendable,
                :create_miner1_payout_commitment,
                :create_miner1_second_commitment_tx,
                :hub_spends_revealing_preimage
