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

require_relative './signatures.rb'

# DSL module for creating and inspecting bitcoin transactions
module Transaction
  include Signatures
  DEFAULT_TX_VERSION = 2

  # Inputs:
  #   tx: raw json transaction loaded from chain
  #   vout: index of the output being spent
  #   script_sig: signature script to spend the above output. This includes tags to direct signature generation.
  # Outputs:
  #   script: Optional script for scriptPubkey
  #   descriptor: Optional descriptor defining the scriptPubkey
  #   policy: Optional miniscript policy defining the scriptPubkey
  #   amount: Value being spent
  def transaction(params)
    params[:inputs].each do |input|
      input[:utxo_details] = get_utxo_details(input[:tx], input[:vout])
    end
    build_transaction params
  end

  def transactions(params)
    params.collect do |tx|
      transaction tx
    end
  end

  def build_transaction(params)
    tx = Bitcoin::Tx.new
    tx.build_params = params
    tx = add_inputs(tx)
    tx = add_outputs(tx)
    tx.version = params[:version] || DEFAULT_TX_VERSION
    add_signatures(tx)
    tx
  end

  def add_input(transaction, input)
    tx_in = Bitcoin::TxIn.new(
      out_point: Bitcoin::OutPoint.from_txid(input[:utxo_details].txid, input[:vout])
    )
    add_csv(transaction, tx_in, input)
    add_cltv(transaction, tx_in, input)
    transaction.in << tx_in
  end

  def add_inputs(transaction)
    return transaction unless transaction.build_params.include? :inputs

    transaction.build_params[:inputs].each do |input|
      add_input(transaction, input)
    end
    transaction
  end

  # Only number of blocks is supported for now.
  #
  # TODO: Switch to libfaketime to generate blocks in the future to
  # support MTP
  def add_csv(transaction, tx_in, input)
    return unless input.include? :csv

    transaction.lock_time = input[:csv]
    tx_in.sequence = input[:csv]
  end

  def add_csv_to_transaction(transaction, index:, csv:)
    transaction.lock_time = csv
    transaction.inputs[index].sequence = csv
    add_signatures(transaction, regen: true)
  end

  # Only number of blocks is supported for now.
  #
  # TODO: Switch to libfaketime to generate blocks in the future to
  # support MTP
  def add_cltv(transaction, tx_in, input)
    return unless input.include? :cltv

    transaction.lock_time = input[:cltv]
    tx_in.sequence = 0
  end

  # Only number of blocks is supported for now.
  #
  # TODO: Switch to libfaketime to generate blocks in the future to
  # support MTP
  def add_cltv_to_transaction(transaction, index:, cltv:)
    transaction.lock_time = cltv
    transaction.inputs[index].sequence = 0
    add_signatures(transaction, regen: true)
  end

  def add_outputs(transaction)
    return transaction unless transaction.build_params.include? :outputs

    # TODO: Handle direct script, without parsing from address
    transaction.build_params[:outputs].each do |output|
      script_pubkey, = build_script_pubkey(output)
      transaction.out << Bitcoin::TxOut.new(value: output[:amount],
                                            script_pubkey: script_pubkey)
    end
    transaction
  end

  def store_witness(pubkey_script, witness)
    return unless witness

    @witness_scripts[pubkey_script] = witness
    print_witness_scripts
  end

  def store_taproot(taproot_details)
    return unless taproot_details

    @taproot_details[taproot_details['address']] = taproot_details
    print_taproot_details
  end

  def print_witness_scripts
    @witness_scripts.each do |addr, script|
      logger.debug "#{addr} ---- #{script}"
    end
  end

  def print_taproot_details
    @taproot_details.each do |addr, details|
      logger.debug "#{addr} ---- #{details}"
    end
  end

  # We don't track witness to script or descriptor. User will have to
  # provide this.
  #
  # We do track the witness for miniscript as the witness there is not
  # easy to figure out for the user.
  def build_script_pubkey(output)
    if output.include? :script
      compile_script_pubkey(output[:script])
    elsif output.include? :policy
      compile_miniscript(output[:policy])
    elsif output.include? :descriptor
      compile_descriptor(output[:descriptor])
    end
  end

  # Return an OpenStruct with txid, index, amount and script pub key
  # for the prevout identified by the method params
  def get_utxo_details(transaction, index)
    # When we pass Bitcoin::Tx, we turn it into hash that matches json-rpc response
    tx = transaction.to_h.with_indifferent_access
    vout = tx[:vout][index]
    script_pubkey = vout['scriptPubKey'] || vout['script_pubkey']
    OpenStruct.new(txid: tx['txid'],
                   index: index,
                   amount: vout['value'],
                   script_pubkey: Bitcoin::Script.parse_from_payload(script_pubkey['hex'].htb))
  end

  # Returns prevouts for all inputs in the tx
  def get_prevouts_for(transaction)
    transaction.build_params[:inputs].map do |input|
      details = get_utxo_details(input[:tx], input[:vout])
      Bitcoin::TxOut.new(value: details.amount.sats, script_pubkey: details.script_pubkey)
    end
  end
end
