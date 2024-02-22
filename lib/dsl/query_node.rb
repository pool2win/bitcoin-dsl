# froze_string_literal: false

# DSL module for querying bitcoin node using json-rpc
module QueryNode
  def get_txid(block:, tx_index:)
    block['tx'][tx_index]['txid']
  end

  def get_script_pubkey(block:, tx_index:, vout_index:)
    Bitcoin::Script.parse_from_payload block['tx'][tx_index]['vout'][vout_index]['scriptPubKey']['hex'].htb
  end

  def get_value(block:, tx_index:, vout_index:)
    (block['tx'][tx_index]['vout'][vout_index]['value'] * SATS).to_i
  end

  def get_height
    getblockchaininfo['blocks']
  end

  def assert_height(height)
    current_height = get_height
    assert_equal current_height, height, "Current height #{current_height} is not at #{height}"
  end

  def get_block_at_height(height)
    blockhash = getblockhash height: height
    getblock hash: blockhash, verbosity: 2
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
    raise "No coinbase found for the given key #{key}"
  end
end
