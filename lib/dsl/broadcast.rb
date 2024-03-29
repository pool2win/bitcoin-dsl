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

# DSL module for broadcasting transactions
module Broadcast
  def extend_chain(to: nil, policy: nil, descriptor: nil, script: nil, num_blocks: 1)
    _ = get_height # We need to seem to call getheight before generating to address
    if descriptor
      script_pubkey, = compile_descriptor(descriptor)
      address = script_pubkey.to_addr
    elsif policy
      script_pubkey, = compile_miniscript(policy)
      address = script_pubkey.to_addr
    elsif script
      script_pubkey, = compile_script_pubkey(script)
      address = script_pubkey.to_addr
    else
      to ||= key :new
      address = to.to_p2wpkh
    end
    result = generatetoaddress num_blocks: num_blocks, to: address
    raise "Unable to extend chaing to #{address}" unless result

    result
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
  def confirm(transaction:, to: nil)
    height = get_height
    to ||= key :new
    extend_chain num_blocks: 1, to: to
    assert_equal height + 1, get_height, 'Tip height mismatch'
    assert_confirmations transaction, confirmations: 1
  end
end
