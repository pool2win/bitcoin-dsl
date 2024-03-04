#  This file is part of Bitcoin-DSL

# Bitcoin-DSL is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# Bitcoin-DSL is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with Bitcoin-DSL. If not, see <https://www.gnu.org/licenses/>.

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

  # Broadcast a transaction
  def broadcast(transaction)
    accepted = testmempoolaccept rawtxs: [transaction.to_hex]
    assert accepted[0]['allowed'], "Transaction not accepted for mempool: \n #{accepted.inspect} \n #{transaction.to_h}"

    assert_equal(sendrawtransaction(tx: transaction.to_hex),
                 transaction.txid,
                 'Sending raw transaction failed')
  end

  # Broadcast multiple transactions
  def broadcast_multiple(transactions)
    accepted = testmempoolaccept rawtxs: transactions.map(&:to_hex)
    assert accepted[0]['allowed'], "Transaction not accepted for mempool: \n #{accepted.inspect}"

    transactions.each do |tx|
      assert_equal(sendrawtransaction(tx: tx.to_hex),
                   tx.txid,
                   'Sending raw transaction failed')
    end
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
