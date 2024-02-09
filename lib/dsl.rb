# frozen_string_literal: false

require 'bitcoin'
require 'open3'
require_relative 'logging'

SATS = 100_000_000

# All the DSL supported functions that are not part of RPC API, go here.
module DSL
  include Logging
  
  def key(params = {})
    if params.is_a?(Hash) && params.include?(:wif)
      Bitcoin::Key.from_wif params[:wif]
    else
      Bitcoin::Key.generate
    end
  end

  def transaction(params)
    tx = Bitcoin::Tx.new
    tx = add_inputs(tx, params) if params.include? :inputs
    tx = add_outputs(tx, params) if params.include? :outputs
    tx.version = params[:version] if params.include? :version
    add_signatures(tx, params) if params.include? :inputs
    tx
  end

  def add_inputs(transaction, params)
    return transaction unless params.include? :inputs

    params[:inputs].each do |input|
      transaction.in << Bitcoin::TxIn.new(out_point: Bitcoin::OutPoint.from_txid(input[:txid], input[:vout]))
    end
    transaction
  end

  def add_outputs(transaction, params)
    return transaction unless params.include? :outputs

    # TODO: Handle direct script, without parsing from address
    params[:outputs].each do |output|
      script_pubkey = build_script_pubkey(output)
      transaction.out << Bitcoin::TxOut.new(value: output[:value],
                                            script_pubkey: script_pubkey)
    end
    transaction
  end

  def build_script_pubkey(output)
    if output.include? :address
      Bitcoin::Script.parse_from_addr(output[:address])
    elsif output.include? :policy
      Bitcoin::Script.parse_from_addr(compile_miniscript(output[:policy]))
    end
  end

  def add_signatures(transaction, params)
    return transaction unless params.include? :inputs

    params[:inputs].each_with_index do |input, index|
      signature = get_signature(transaction, input, index)
      transaction.in[index].script_witness.stack << signature << input[:signature][:signed_by].pubkey.htb
    end
    transaction
  end

  def get_signature(transaction, input, index)
    sig_hash = transaction.sighash_for_input(index,
                                             input[:signature][:script_pubkey],
                                             sig_version: input[:signature][:segwit_version],
                                             amount: 50 * SATS)
    input[:signature][:signed_by].sign(sig_hash) +
      [Bitcoin::SIGHASH_TYPE[input[:signature][:sighash]]].pack('C')
  end

  def get_txid(block:, tx_index:)
    block['tx'][tx_index]['txid']
  end

  def get_script_pubkey(block:, tx_index:, vout_index:)
    Bitcoin::Script.parse_from_payload block['tx'][tx_index]['vout'][vout_index]['scriptPubKey']['hex'].htb
  end

  def get_value(block:, tx_index:, vout_index:)
    (block['tx'][tx_index]['vout'][vout_index]['value'] * SATS).to_i
  end

  def compile_miniscript(script)
    policy = script.gsub!(/(\$)(\w+)/) { instance_eval("@#{Regexp.last_match(-1)}", __FILE__, __LINE__).pubkey }
    output = `miniscript-cli -m '#{policy}'`
    raise "Error parsing policy #{policy}" if output.empty?

    result = output.split("\n")
    logger.debug "Script: #{result[0]}"
    logger.debug "scriptpubkey: #{result[1]}"
    result[2].strip # return the Wsh wrapped descriptor
  end

  def pretty_print(result)
    JSON.pretty_generate result
  end
end
