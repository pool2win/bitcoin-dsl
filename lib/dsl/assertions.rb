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
    'signature verified'
  end

  def assert_mempool_accept(*transactions)
    accepted = testmempoolaccept rawtxs: transactions.map(&:to_hex)
    assert accepted[0]['allowed'], "Transaction not accepted for mempool.\n#{accepted}"
    'acceptable'
  end

  def assert_not_mempool_accept(*transactions)
    accepted = testmempoolaccept rawtxs: transactions.map(&:to_hex)
    assert !accepted[0]['allowed'], 'Transaction accepted by mempool when it should not be'
    'not acceptable'
  end

  def assert_height(height)
    current_height = get_height
    assert_equal current_height, height, "Current height #{current_height} is not at #{height}"
    height
  end

  def assert_confirmed(transaction:, at_height: nil, txid: nil)
    at_height ||= get_height
    blockhash = getblockhash height: at_height
    txid ||= transaction.txid if transaction
    tx = getrawtransaction txid: txid, verbose: true, block: blockhash['hash']
    assert_equal blockhash, tx['blockhash'], "Transaction #{txid} not confirmed"
    'Transaction confirmed'
  end

  def assert_confirmations(transaction, confirmations: 1)
    tx = transaction.to_h.with_indifferent_access
    rawtx = getrawtransaction transaction: tx['txid'], verbose: true
    assert false, 'Transaction not found' unless rawtx
    assert false, 'No confirmations found' unless rawtx.include?('confirmations')
    assert rawtx['confirmations'] >= confirmations, "Transaction confirmations: #{rawtx['confirmations']}"
    "Transaction has #{rawtx['confirmations']} confirmations"
  end

  # This assertion iterates over all blocks from transaction conf
  # height to chain height.
  #
  # Use with care.
  def assert_output_is_spent(transaction:, vout:)
    transaction = transaction.to_h
    tx = getrawtransaction txid: transaction['txid'], verbose: true
    assert false, 'No such transaction found' unless tx
    assert false, 'Transaction not yet confirmed' unless tx['confirmations']

    chain_height = get_height
    confirmation_block = getblock blockhash: tx['blockhash']
    assert false, 'No block confirmation found for transaction' unless confirmation_block

    confirmation_blockheight = confirmation_block['height']
    assert false, 'Chain height at transaction confirmation' unless chain_height >= confirmation_blockheight

    spent = spent_between_heights?(confirmation_blockheight, chain_height, txid: transaction['txid'], vout: vout)
    assert spent, 'Specified output not yet spent'
    'Output is spent'
  end

  # This assertion iterates over all blocks from transaction conf
  # height to chain height.
  #
  # Use with care.
  def assert_output_is_not_spent(transaction:, vout:)
    transaction = transaction.to_h
    tx = getrawtransaction txid: transaction['txid'], verbose: true
    return if tx.nil? || !tx.include?('confirmations')

    chain_height = get_height
    confirmation_block = getblock blockhash: tx['blockhash']
    return unless confirmation_block

    confirmation_blockheight = confirmation_block['height']
    return unless chain_height >= confirmation_blockheight

    spent = spent_between_heights?(confirmation_blockheight, chain_height, txid: transaction['txid'], vout: vout)
    assert !spent, 'Specified output already spent'
    'Output is not spent'
  end

  def spent_between_heights?(from, to, txid:, vout:)
    (from..to).any? do |height|
      blockhash = getblockhash height: height
      block = getblock blockhash: blockhash, verbose: true
      block['tx'].any? do |input_txid|
        input_tx = getrawtransaction txid: input_txid, verbose: true
        input_tx['vin'].any? do |input|
          input['txid'] == txid && input['vout'] == vout
        end
      end
    end
  end
end
