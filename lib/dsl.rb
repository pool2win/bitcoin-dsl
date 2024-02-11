# frozen_string_literal: false

require 'bitcoin'
require 'open3'
require 'ostruct'
require_relative 'logging'

SATS = 100_000_000

# All the DSL supported functions that are not part of RPC API, go here.
module DSL
  include Logging
  DEFAULT_TX_VERSION = 2
  DEFAULT_SEGWIT_VERSION = :witness_v0
  DEFAULT_SIGHASH_TYPE = :all

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
    tx.version = params[:version] || DEFAULT_TX_VERSION
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
                                             sig_version:
                                               input.dig(:signature, :segwit_version) || DEFAULT_SEGWIT_VERSION,
                                             amount: input[:signature][:amount])
    sighash_type = input.dig(:signature, :sighash) || DEFAULT_SIGHASH_TYPE
    input[:signature][:signed_by].sign(sig_hash) + [Bitcoin::SIGHASH_TYPE[sighash_type]].pack('C')
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

  def extend_chain(to:, num_blocks: 1)
    logger.debug "Extending chain by #{num_blocks} blocks"
    address = to.to_p2wpkh
    blockhashes = generatetoaddress num_blocks: num_blocks, to: address
    blockhashes.each do |blockhash|
      block = getblock hash: blockhash, verbosity: 2
      @txid_signers[get_txid(block: block, tx_index: 0)] = to
    end
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

  def get_height
    getblockchaininfo['blocks']
  end

  def get_block_at_height(height)
    blockhash = getblockhash height: height
    getblock hash: blockhash, verbosity: 2
  end

  def assert_confirmed(txid:, height:)
    blockhash = getblockhash height: height
    tx = getrawtransaction txid: txid, verbose: true, block: blockhash
    assert tx['in_active_chain'], "Transaction #{txid} not confirmed"
  end

  def extract_txid_vout(blockheight:, tx_index:, vout_index:)
    block = get_block_at_height blockheight

    amount = get_value block: block, tx_index: tx_index, vout_index: vout_index
    txid = get_txid block: block, tx_index: tx_index
    script_pubkey = get_script_pubkey block: block, tx_index: tx_index, vout_index: vout_index

    OpenStruct.new(amount: amount, txid: txid, script_pubkey: script_pubkey)
  end

  # Verify transaction input is properly signed
  def verify_signature(transaction:, index:, script_pubkey:, amount:)
    verification_result = transaction.verify_input_sig(index, script_pubkey, amount: amount)
    assert verification_result, 'Input signature verification failed'
  end

  # Broadcast the transaction
  def broadcast(transaction:)
    accepted = testmempoolaccept rawtxs: [transaction.to_hex]
    assert accepted[0]['allowed'], "Alice boarding tx not accepted #{accepted.inspect}"

    assert_equal(sendrawtransaction(tx: transaction.to_hex),
                 transaction.txid,
                 'Sending raw transaction failed')
  end

  # Confirm transaction, by mining block to given address
  def confirm(transaction:, to:)
    height = get_height
    extend_chain num_blocks: 1, to: to
    assert_equal height + 1, get_height, 'Tip height mismatch'
    assert_confirmed txid: transaction.txid, height: height + 1
  end

  def spend_coinbase(height:, signed_by:, to_script:, amount:, new_coinbase_to:)
    utxo_details = extract_txid_vout blockheight: height, tx_index: 0, vout_index: 0
    tx = create_tx(utxo_details: utxo_details, signed_by: signed_by, to_script: to_script, amount: amount)
    verify_signature transaction: tx,
                     index: 0,
                     script_pubkey: utxo_details.script_pubkey,
                     amount: utxo_details.amount
    broadcast transaction: tx
    confirm transaction: tx, to: new_coinbase_to
  end

  def create_tx(utxo_details:, signed_by:, to_script:, amount:)
    transaction inputs: [
                  {
                    txid: utxo_details.txid,
                    vout: 0,
                    signature: { signed_by: signed_by, script_pubkey: utxo_details.script_pubkey, amount: utxo_details.amount }
                  }
                ],
                outputs: [
                  { policy: to_script, value: amount }
                ]
  end

  def spend_utxo(txid:, vout:, to_script:); end

  def pretty_print(result)
    JSON.pretty_generate result
  end
end
