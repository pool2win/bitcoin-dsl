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
      get_components(input[:script_sig]).each do |component|
        if component[:type] == :opcode
          stack << Bitcoin::Script.from_string(component[:expression]).to_payload
        else
          send("handle_#{component[:type]}", transaction, input, index, component[:expression])
        end
      end
      append_witness_to_stack(input, stack)
    end

    def append_witness_to_stack(input, stack)
      return unless @witness_scripts.include? input[:utxo_details].script_pubkey.to_addr

      stack << @witness_scripts[input[:utxo_details].script_pubkey.to_addr].to_payload
    end

    def handle_wpkh(transaction, input, index, key)
      key = get_key_and_sign(transaction, input, index, key)
      transaction.inputs[index].script_witness.stack << key.pubkey.htb
    end

    def handle_multisig(transaction, input, index, keys)
      handle_nulldummy(transaction, input, index, keys) # Empty byte for that infamous multisig validation bug
      keys.each do |key|
        get_key_and_sign(transaction, input, index, key)
      end
    end

    def handle_sig(transaction, input, index, key)
      get_key_and_sign(transaction, input, index, key)
    end

    def handle_sig_tr_keypath(transaction, input, index, key)
      get_key_and_sign(transaction, input, index, key, :taproot)
    end

    def handle_sig_tr_scriptpath(transaction, input, index, key); end

    def handle_nulldummy(transaction, _input, index, _keys)
      transaction.inputs[index].script_witness.stack << ''
    end

    def handle_datum(transaction, _input, index, datum)
      transaction.inputs[index].script_witness.stack << datum
    end

    def get_key_and_sign(transaction, input, index, key, taproot = nil)
      stack = transaction.inputs[index].script_witness.stack
      return if key == '_skip'
      stack << '' and return if key == '_empty'

      begin
        key = Bitcoin::Key.from_wif(key)
      rescue ArgumentError
        key = instance_eval(key, __FILE__, __LINE__)
      end
      stack << get_signature(transaction, input, index, key, taproot)
      key
    end

    def get_components(script)
      script.split.collect do |element|
        case element
        when /sig:wpkh\((.*)\)/
          { type: :wpkh, expression: Regexp.last_match[1] }
        when /sig:multi\((.*)\)/
          { type: :multisig, expression: Regexp.last_match[1].split(',').map(&:strip) }
        when /sig:tr:keypath\((.*)\)/
          { type: :sig_tr_keypath, expression: Regexp.last_match[1] }
        when /sig:tr:scriptpath\((.*)\)/
          { type: :sig_tr_scriptpath, expression: Regexp.last_match[1].split(',').map(&:strip) }
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
  end
end
