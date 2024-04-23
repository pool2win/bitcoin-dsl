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

require_relative './element'

# DSL module for compiling miniscript and generating script sig
module ScriptCompiler
  # Compile script sig
  module ScriptSig
    include CompileScript::ParseElement

    # Compile a scriptSig, replacing `sig:pk` with a signature by pk.
    # Return an array of components that will be concatenated into the witness stack
    def compile_script_sig(transaction, input, index)
      stack = transaction.inputs[index].script_witness.stack
      if input[:script_sig].is_a? String
        parse_string_script_sig(transaction, input, index, input[:script_sig])
      else
        parse_hash_script_sig(transaction, input, index)
      end
      append_witness_to_stack(input, stack)
    end

    def parse_string_script_sig(transaction, input, index, script_sig, opts: {})
      get_components(script_sig).each do |component|
        if component[:type] == :opcode
          stack << Bitcoin::Script.from_string(component[:expression]).to_payload
        else
          send("handle_#{component[:type]}", transaction, input, index, component[:expression], opts)
        end
      end
    end

    def parse_hash_script_sig(transaction, input, index)
      return unless taproot? input[:script_sig]

      if input[:script_sig].key? :keypath
        builder = @taproot_details[input[:utxo_details].script_pubkey.to_addr]
        tweaked_key = builder.tweak_private_key(input[:script_sig][:keypath])
        get_key_and_sign(transaction, input, index, tweaked_key, { sig_version: :taproot })
      elsif input[:script_sig].key? :leaf_index
        sign_using_script_path(transaction, input, index)
      end
    end

    def sign_using_script_path(transaction, input, index)
      taproot_input_details = @taproot_details[input[:utxo_details].script_pubkey.to_addr]
      leaf_index = input[:script_sig][:leaf_index]
      leaf = taproot_input_details.branches[leaf_index / 2][leaf_index % 2]
      logger.debug "Signing using leaf index: #{leaf_index} and script: #{leaf.script}"
      parse_string_script_sig(transaction, input, index, input[:script_sig][:sig],
                              opts: { leaf_hash: leaf.leaf_hash, sig_version: :tapscript })
      transaction.inputs[index].script_witness.stack << leaf.script.to_payload
      transaction.inputs[index].script_witness.stack << taproot_input_details.control_block(leaf).to_payload
    end

    def append_witness_to_stack(input, stack)
      return unless @witness_scripts.include? input[:utxo_details].script_pubkey.to_addr

      stack << @witness_scripts[input[:utxo_details].script_pubkey.to_addr].to_payload
    end

    def handle_wpkh(transaction, input, index, key, opts)
      key = get_key_and_sign(transaction, input, index, key, opts)
      transaction.inputs[index].script_witness.stack << key.pubkey.htb
    end

    def handle_multisig(transaction, input, index, keys, opts)
      handle_nulldummy(transaction, input, index, keys, opts) # Empty byte for that infamous multisig validation bug
      keys.each do |key|
        get_key_and_sign(transaction, input, index, key, opts)
      end
    end

    def handle_sig(transaction, input, index, key, opts)
      get_key_and_sign(transaction, input, index, key, opts)
    end

    def handle_sig_keypath(transaction, input, index, key, opts)
      get_key_and_sign(transaction, input, index, key, opts)
    end

    def handle_nulldummy(transaction, _input, index, _keys, _opts)
      transaction.inputs[index].script_witness.stack << ''
    end

    def handle_datum(transaction, _input, index, datum, _opts)
      transaction.inputs[index].script_witness.stack << datum
    end

    def get_key_and_sign(transaction, input, index, key, opts)
      stack = transaction.inputs[index].script_witness.stack
      return if key == '_skip'
      stack << '' and return if key == '_empty'

      key = get_key(key)
      stack << get_signature(transaction, input, index, key, opts)
      key
    end

    def get_key(key)
      return key if key.is_a? Bitcoin::Key

      begin
        Bitcoin::Key.from_wif(key)
      rescue ArgumentError
        instance_eval(key, __FILE__, __LINE__)
      end
    end

    def get_components(script)
      script.split.collect do |element|
        case element
        when /sig:wpkh\((.*)\)/
          { type: :wpkh, expression: Regexp.last_match[1] }
        when /sig:multi\((.*)\)/
          { type: :multisig, expression: Regexp.last_match[1].split(',').map(&:strip) }
        when /sig:(.*)/
          { type: :sig, expression: Regexp.last_match[1] }
        when /nulldummy/
          { type: :nulldummy }
        when /0[xX][0-9a-fA-F]+/
          { type: :datum, expression: Bitcoin.pack_var_int(Regexp.last_match[0].to_i(16)) }
        else
          parse_element(element)
        end
      end
    end

    def taproot?(script)
      script.is_a? Hash and (script.include?(:keypath) || script.include?(:leaf_index))
    end
  end
end
