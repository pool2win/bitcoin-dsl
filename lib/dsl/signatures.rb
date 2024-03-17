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

# DSL module for creating and inspecting bitcoin transactions
module Signatures
  DEFAULT_SEGWIT_VERSION = :witness_v0
  DEFAULT_SIGHASH_TYPE = :all

  def add_signatures(transaction, regen: false)
    return transaction unless transaction.build_params.include? :inputs

    transaction.build_params[:inputs].each_with_index do |input, index|
      if regen # reset stack if regenerating all signatures
        transaction.inputs[index].script_witness = Bitcoin::ScriptWitness.new
      end
      compile_script_sig(transaction, input, index, transaction.inputs[index].script_witness.stack)
    end
    transaction
  end

  # Regenerate the script sig witness stack for_tx input at_index with
  # the given script sig
  def update_script_sig(for_tx:, at_index:, with_script_sig:)
    input = for_tx.build_params[:inputs][at_index]
    input[:script_sig] = with_script_sig
    for_tx.inputs[at_index].script_witness = Bitcoin::ScriptWitness.new
    compile_script_sig(for_tx, input, at_index, for_tx.inputs[at_index].script_witness.stack)
  end

  def get_signature(transaction, input, index, key)
    prevout_output_script = get_prevout_script(input)
    logger.debug "PREVOUT FOUND #{prevout_output_script}"
    sig_hash = transaction.sighash_for_input(index,
                                             prevout_output_script,
                                             sig_version: DEFAULT_SEGWIT_VERSION,
                                             amount: input[:utxo_details].amount.sats)
    sighash_type = input[:sighash] || DEFAULT_SIGHASH_TYPE
    key.sign(sig_hash) + [Bitcoin::SIGHASH_TYPE[sighash_type]].pack('C')
  end

  def get_prevout_script(input)
    logger.debug "GETTING PREVOUT SCRIPT... #{input[:utxo_details].script_pubkey.to_addr}"
    if @witness_scripts.include?(input[:utxo_details].script_pubkey.to_addr)
      @witness_scripts[input[:utxo_details].script_pubkey.to_addr]
    else
      input[:utxo_details].script_pubkey
    end
  end
end
