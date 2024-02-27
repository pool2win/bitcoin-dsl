# frozen_string_literal: false

# DSL module for broadcasting transactions
module Broadcast
  def extend_chain(to: nil, num_blocks: 1)
    from_height = get_height
    to ||= key :new
    address = to.to_p2wpkh
    logger.info "Extending chain by #{num_blocks} blocks to address #{address}"
    generatetoaddress num_blocks: num_blocks, to: address
  end

  # Broadcast the transaction
  def broadcast(transaction:)
    accepted = testmempoolaccept rawtxs: [transaction.to_hex]
    assert accepted[0]['allowed'], "Transaction not accepted for mempool: \n #{accepted.inspect} \n #{transaction.to_h}"

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
end
