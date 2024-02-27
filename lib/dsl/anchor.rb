# frozen_string_literal: false

# Methods to handle transaction anchoring
module Anchor
  # Anchor transaction to the other transaction by creating an output
  # and using it as an input. The output is sent to dust_for using
  # p2wpkh
  def anchor(transaction:, to:, dust_for:, amount: 1000)
    # Add a new dust output to transaction paying to dust_for
    setup_dust_output(to, amount, dust_for)
    setup_dust_input(transaction, to, dust_for)
  end

  def setup_dust_output(to, amount, dust_for)
    out = Bitcoin::TxOut.new(value: amount,
                             script_pubkey: Bitcoin::Script.parse_from_addr(dust_for.to_p2wpkh))
    to.outputs << out
    add_signatures(to, regen: true)
  end

  def setup_dust_input(transaction, to, dust_for)
    new_output_index = to.outputs.size - 1
    utxo_details = get_utxo_details(to, new_output_index)
    input = { tx: to, vout: new_output_index, script_sig: "p2wpkh:#{dust_for.to_wif}",
              utxo_details: utxo_details }
    add_input(transaction, input)
    transaction.build_params[:inputs] << input
    add_signatures(transaction, regen: true)
  end
end
