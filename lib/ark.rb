# frozen_string_literal: false

pretty_print getblockchaininfo

alice = key :new
asp = key :new

address = alice.to_p2pkh
generatetoaddress 1, address

blockhash = getblockhash 1

block = getblock blockhash, 2

coinbase_txid = block['tx'][0]['txid']

alice_boarding_tx = transaction inputs: [
                                  { txid: coinbase_txid,
                                    vout: 0,
                                    sighash: :all,
                                    signed_by: alice }
                                ],
                                outputs: [
                                  { address: asp.to_p2pkh,
                                    amount: 1_000_000 }
                                ],
                                version: 2

puts alice_boarding_tx
