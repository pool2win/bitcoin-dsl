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
      if input.include? :txid
        txid = input[:txid]
      elsif input.include? :tx
        txid = input[:tx].txid
      end
      transaction.in << Bitcoin::TxIn.new(out_point: Bitcoin::OutPoint.from_txid(txid, input[:vout]))
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
    segwit_version = input.dig(:signature, :segwit_version) || DEFAULT_SEGWIT_VERSION
    sig_hash = transaction.sighash_for_input(index,
                                             input[:signature][:script_pubkey],
                                             sig_version: segwit_version,
                                             amount: input[:signature][:amount])
    sighash_type = input.dig(:signature, :sighash) || DEFAULT_SIGHASH_TYPE
    input[:signature][:signed_by].sign(sig_hash) + [Bitcoin::SIGHASH_TYPE[sighash_type]].pack('C')
  end

  # Verify transaction input is properly signed
  def verify_signature(transaction:, index:, script_pubkey:, amount:)
    verification_result = transaction.verify_input_sig(index, script_pubkey, amount: amount)
    assert verification_result, 'Input signature verification failed'
  end

  def create_tx(utxo_details:, signed_by:, output_script:, amount:)
    transaction inputs: [
                  {
                    txid: utxo_details.txid,
                    vout: 0,
                    signature: { signed_by: signed_by,
                                 script_pubkey: utxo_details.script_pubkey,
                                 amount: utxo_details.amount }
                  }
                ],
                outputs: [
                  { policy: output_script, value: amount }
                ]
  end
end
