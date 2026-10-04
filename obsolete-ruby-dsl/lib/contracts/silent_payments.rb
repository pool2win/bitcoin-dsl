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

# tag::silent-payment[]
@sender_input_key = key :new # <1>
@sender = key :new
@receiver = key even_y: true # Generate a key with even y

extend_chain to: @sender_input_key, num_blocks: 101

@sender_coinbase = spendable_coinbase_for @sender_input_key # <2>

@sender_dh_share = multiply point: @receiver, scalar: @sender_input_key # <3>

@taproot_output_key = tweak_public_key @receiver, with: hash160(@sender_dh_share) # <3>

@taproot_output_tx = transaction inputs: [{ tx: @sender_coinbase,
                                            vout: 0,
                                            script_sig: 'sig:wpkh(@sender_input_key)' }],
                                 outputs: [{ amount: 49.999.sats,
                                             taproot: { internal_key: @taproot_output_key } }]

broadcast @taproot_output_tx

confirm transaction: @taproot_output_tx
extend_chain num_blocks: 100

assert_equal @taproot_output_tx.inputs[0].script_witness.stack[1].bth, @sender_input_key.pubkey

@receiver_dh_share = multiply point: @sender_input_key, scalar: @receiver # <4>
@receiver_tweaked_private_key = tweak_private_key @receiver, with: hash160(@receiver_dh_share) # <4>

@spend_received_payment_tx = transaction inputs: [{ tx: @taproot_output_tx,
                                                    vout: 0,
                                                    script_sig: { keypath: @receiver_tweaked_private_key } }], # <5>
                                         outputs: [{ amount: 49.998.sats,
                                                     descriptor: 'wpkh(@sender)' }]

assert_mempool_accept @spend_received_payment_tx
broadcast @spend_received_payment_tx
confirm transaction: @spend_received_payment_tx
# end::silent-payment[]
