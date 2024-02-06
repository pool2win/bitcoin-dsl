# frozen_string_literal: false

puts node :getblockchaininfo

# node :createwallet, :alice
# node :loadwallet, :alice

# wallet_info = node :getwalletinfo
# print_result wallet_info

# Get an address from loaded wallet
# address = node :getnewaddress

alice = key :new

asp = key :new

p alice.to_p2pkh
# address = alice.to_p2pkh
# node :generatetoaddress, 10, address

# alice_boarding_tx = transaction inputs: [
#                                   { txid: '319b8446684478f3f0e48fc9d8401101e6033f6c3640ccd498874be97e99bdeb',
#                                     vout: 0,
#                                     sighash: :all,
#                                     signed_by: alice }
#                                 ],
#                                 outputs: [
#                                   { address: asp.to_p2pkh,
#                                     amount: 1000 }
#                                 ],
#                                 version: 2
