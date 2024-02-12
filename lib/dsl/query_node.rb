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

  def get_block_at_height(height)
    blockhash = getblockhash height: height
    getblock hash: blockhash, verbosity: 2
  end

  def assert_confirmed(txid:, height:)
    blockhash = getblockhash height: height
    tx = getrawtransaction txid: txid, verbose: true, block: blockhash
    assert tx['in_active_chain'], "Transaction #{txid} not confirmed"
  end

  def extract_txid_vout(blockheight:, tx_index:, vout_index:)
    block = get_block_at_height blockheight

    amount = get_value block: block, tx_index: tx_index, vout_index: vout_index
    txid = get_txid block: block, tx_index: tx_index
    script_pubkey = get_script_pubkey block: block, tx_index: tx_index, vout_index: vout_index

    OpenStruct.new(amount: amount, txid: txid, script_pubkey: script_pubkey)
  end
end
