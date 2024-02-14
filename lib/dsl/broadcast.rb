# froze_string_literal: false

# DSL module for broadcasting transactions
module Broadcast
  def extend_chain(to:, num_blocks: 1)
    address = to.to_p2wpkh
    logger.debug "Extending chain by #{num_blocks} blocks to address #{address}"
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
  # Returns raw transaction loaded from the bitcoin node
  def confirm(transaction:, to:)
    height = get_height
    extend_chain num_blocks: 1, to: to
    assert_equal height + 1, get_height, 'Tip height mismatch'
    assert_confirmed transaction: transaction, at_height: height + 1
  end

  # Inputs:
  #   tx: raw json transaction loaded from chain
  #   vout: index of the output being spent
  #   script_sig: signature script to spend the above output. This includes tags to direct signature generation.
  # Outputs:
  #   script: Optional script for scriptPubkey
  #   address: Optional address to derice scriptPubkey from
  #   amount: Value being spent
  def spend(inputs:, outputs:)
    inputs.each do |input|
      input[:utxo_details] = get_utxo_details(input[:tx], input[:vout])
    end
    transaction inputs: inputs,
                outputs: outputs
  end
end
