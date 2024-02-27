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
end
