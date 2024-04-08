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

# DSL module for querying bitcoin node using json-rpc
module QueryNode
  def get_txid(block:, tx_index:)
    block['tx'][tx_index]['txid']
  end

  def get_script_pubkey(block:, tx_index:, vout_index:)
    Bitcoin::Script.parse_from_payload block['tx'][tx_index]['vout'][vout_index]['scriptPubKey']['hex'].htb
  end

  def get_value(block:, tx_index:, vout_index:)
    (block['tx'][tx_index]['vout'][vout_index]['value'].sats).to_i
  end

  def get_height
    getblockchaininfo['blocks']
  end

  def get_block_at_height(height)
    blockhash = getblockhash height: height
    getblock hash: blockhash, verbosity: 2
  end

  # def get_utxo_details(blockheight:, tx_index:, vout_index:)
  #   block = get_block_at_height blockheight

  #   amount = get_value block: block, tx_index: tx_index, vout_index: vout_index
  #   txid = get_txid block: block, tx_index: tx_index
  #   script_pubkey = get_script_pubkey block: block, tx_index: tx_index, vout_index: vout_index

  #   OpenStruct.new(amount: amount, txid: txid, script_pubkey: script_pubkey)
  # end

  def get_coinbase_at(height)
    block = get_block_at_height height
    block['tx'][0]
  end

  # Return a spendable coinbase for a key
  # If a key is provided, we use the p2wpkh address for the key
  # Later on we will add options to query by a given address
  def spendable_coinbase_for(key, height: nil)
    address = key.to_p2wpkh
    height ||= get_height - 100
    (1..height).each do |h|
      coinbase = get_coinbase_at h
      return coinbase if coinbase['vout'][0]['scriptPubKey']['address'] == address
    end
    raise 'No coinbase found for the given key'
  end

  def get_block_confirmed_at(transaction:)
    tx = getrawtransaction txid: transaction.txid, verbose: true
    return 'No such transaction found' unless tx

    tx['blockhash']
  end
end
