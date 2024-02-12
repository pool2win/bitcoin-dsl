# froze_string_literal: false

# DSL module for broadcasting transactions
module Broadcast
  def extend_chain(to:, num_blocks: 1)
    logger.debug "Extending chain by #{num_blocks} blocks"
    address = to.to_p2wpkh
    blockhashes = generatetoaddress num_blocks: num_blocks, to: address
    blockhashes.each do |blockhash|
      block = getblock hash: blockhash, verbosity: 2
      @txid_signers[get_txid(block: block, tx_index: 0)] = to
    end
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
    assert_confirmed transaction: transaction, at_height: height + 1
  end

  # Spend the coinbase transaction at the given height.
  # Return the spending transaction.
  def spend_coinbase(height:, signed_by:, to_script:, amount:, new_coinbase_to:)
    utxo_details = extract_txid_vout blockheight: height, tx_index: 0, vout_index: 0
    tx = create_tx(utxo_details: utxo_details, signed_by: signed_by, to_script: to_script, amount: amount)
    verify_signature transaction: tx,
                     index: 0,
                     script_pubkey: utxo_details.script_pubkey,
                     amount: utxo_details.amount
    broadcast transaction: tx
    confirm transaction: tx, to: new_coinbase_to
    tx
  end

  def spend_utxo(txid:, vout:, to_script:); end
end
