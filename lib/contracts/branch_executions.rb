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

# tag::setup[]
state_transition :setup do
  # Generate new keys
  @alice = key :new
  @bob = key :new

  # Mine to an address with miniscript policy with CSV
  extend_chain num_blocks: 1, policy: 'or(and(older(10),pk(@alice)),pk(@bob))' # <1>

  # Make coinbase at block 1 spendable
  extend_chain num_blocks: 100 # <2>
end
# end::setup[]

# tag::bob_spends_immediately[]
state_transition :bob_spends_immediately do
  # Load the coinbase with miniscript policy
  @alice_coinbase_tx = get_coinbase_at 1

  @csv_tx = transaction inputs: [
                          {
                            tx: @alice_coinbase_tx,
                            vout: 0,
                            script_sig: 'sig:@bob' # <1>
                          }
                        ],
                        outputs: [
                          {
                            descriptor: 'wpkh(@alice)',
                            amount: 49.998.sats
                          }
                        ]

  assert_mempool_accept @csv_tx

  broadcast @csv_tx # <2>
  extend_chain # <2>
end
# end::bob_spends_immediately[]

# tag::run_bob_spends_immediately_transistions[]
run_transitions :setup, :bob_spends_immediately
# end::run_bob_spends_immediately_transistions[]

# tag::alice_cant_spend[]
state_transition :alice_cant_spend do
  # Load the coinbase with miniscript policy
  @alice_coinbase_tx = get_coinbase_at 1

  @csv_tx = transaction inputs: [
                          {
                            tx: @alice_coinbase_tx,
                            vout: 0,
                            script_sig: 'sig:@alice ""' # <1>
                          }
                        ],
                        outputs: [
                          {
                            descriptor: 'wpkh(@alice)',
                            amount: 49.998.sats
                          }
                        ]

  assert_not_mempool_accept @csv_tx # <2>
end
# end::alice_cant_spend[]

# tag::run_alice_cant_spend_transistions[]
run_transitions :reset, :setup, :alice_cant_spend
# end::run_alice_cant_spend_transistions[]

# tag::alice_spends_after_delay[]
state_transition :alice_spends_after_delay do
  # Load the coinbase with miniscript policy
  @alice_coinbase_tx = get_coinbase_at 1

  @csv_tx = transaction inputs: [
                          {
                            tx: @alice_coinbase_tx,
                            vout: 0,
                            script_sig: 'sig:@alice ""', # <1>
                            csv: 10 # <2>
                          }
                        ],
                        outputs: [
                          {
                            descriptor: 'wpkh(@alice)',
                            amount: 49.998.sats
                          }
                        ]

  extend_chain num_blocks: 10 # <3>

  broadcast @csv_tx # <4>
  extend_chain
end
# end::alice_spends_after_delay[]

# tag::run_alice_spends_transistions[]
run_transitions :reset, :setup, :alice_spends_after_delay
# end::run_alice_spends_transistions[]
