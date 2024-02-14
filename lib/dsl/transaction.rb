# froze_string_literal: false

# DSL module for creating and inspecting bitcoin transactions
module Transaction
  DEFAULT_TX_VERSION = 2
  DEFAULT_SEGWIT_VERSION = :witness_v0
  DEFAULT_SIGHASH_TYPE = :all

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
      transaction.in << Bitcoin::TxIn.new(out_point: Bitcoin::OutPoint.from_txid(input[:utxo_details].txid, input[:vout]))
    end
    transaction
  end

  def add_outputs(transaction, params)
    return transaction unless params.include? :outputs

    # TODO: Handle direct script, without parsing from address
    params[:outputs].each do |output|
      script_pubkey = build_script_pubkey(output)
      transaction.out << Bitcoin::TxOut.new(value: output[:amount],
                                            script_pubkey: script_pubkey)
    end
    transaction
  end

  def build_script_pubkey(output)
    if output.include? :address
      address = parse_address(output[:address])
      Bitcoin::Script.parse_from_addr(address)
    elsif output.include? :policy
      Bitcoin::Script.parse_from_addr(compile_miniscript(output[:policy]))
    end
  end

  def add_signatures(transaction, params)
    return transaction unless params.include? :inputs

    params[:inputs].each_with_index do |input, index|
      compile_script_sig(transaction, input, index, transaction.in[index].script_witness.stack)
    end
    transaction
  end

  def get_signature(transaction, input, index, key)
    sig_hash = transaction.sighash_for_input(index,
                                             input[:utxo_details].script_pubkey,
                                             sig_version: DEFAULT_SEGWIT_VERSION,
                                             amount: input[:utxo_details].amount * SATS)
    sighash_type = input[:sighash] || DEFAULT_SIGHASH_TYPE
    key.sign(sig_hash) + [Bitcoin::SIGHASH_TYPE[sighash_type]].pack('C')
  end

  def get_utxo_details(transaction, vout)
    tx = transaction.to_h # When we pass Bitcoin::Tx, we turn it into hash that matches json-rpc response
    vout = tx['vout'][vout]
    OpenStruct.new(txid: tx['txid'],
                   amount: vout['value'],
                   script_pubkey: Bitcoin::Script.parse_from_payload(vout['scriptPubKey']['hex'].htb))
  end

  # Verify transaction input is properly signed
  def verify_signature(for_transaction:, at_index:, with_prevout:)
    utxo_details = get_utxo_details(with_prevout[0], with_prevout[1])
    verification_result = for_transaction.verify_input_sig(at_index,
                                                           utxo_details.script_pubkey,
                                                           amount: utxo_details.amount * SATS)
    assert verification_result, 'Input signature verification failed'
  end
end
