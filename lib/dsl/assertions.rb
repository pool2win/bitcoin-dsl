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

# Methods for asserts
module Assertions
  # Verify transaction input is properly signed
  def verify_signature(for_transaction:, at_index:, with_prevout:)
    utxo_details = get_utxo_details(with_prevout[0], with_prevout[1])
    verification_result = for_transaction.verify_input_sig(at_index,
                                                           utxo_details.script_pubkey,
                                                           amount: utxo_details.amount.sats)
    assert verification_result, 'Input signature verification failed'
  end

  def assert_mempool_accept(*transactions)
    accepted = testmempoolaccept rawtxs: transactions.map(&:to_hex)
    assert accepted[0]['allowed'], "Transaction not accepted for mempool.\n#{accepted}"
  end

  def assert_not_mempool_accept(*transactions)
    accepted = testmempoolaccept rawtxs: transactions.map(&:to_hex)
    assert !accepted[0]['allowed'], 'Transaction accepted by mempool when it should not be'
  end

  def assert_height(height)
    current_height = get_height
    assert_equal current_height, height, "Current height #{current_height} is not at #{height}"
  end

  # Assert the provided transaction is spent on chain
  # Returns the raw transaction loaded from the chain
  def assert_confirmed(transaction:, at_height: nil, txid: nil)
    at_height ||= get_height
    blockhash = getblockhash height: at_height
    txid ||= transaction.txid if transaction
    tx = getrawtransaction txid: txid, verbose: true, block: blockhash['hash']
    assert_equal blockhash, tx['blockhash'], "Transaction #{txid} not confirmed"
    tx
  end

  def assert_confirmations(transaction, confirmations: 1)
    rawtx = getrawtransaction transaction: transaction.txid, verbose: true
    assert false, 'Transaction not found' unless rawtx
    assert rawtx['confirmations'] >= confirmations, "Transaction confirmations only at #{rawtx['confirmations']}"
  end
end
