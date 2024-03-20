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

require_relative '../lib/runner'

RSpec.shared_examples 'script evaluation' do |script_file|
  it 'should run successfully' do
    expect do
      subject.run script_file
    end.not_to raise_error
  end
end

RSpec.describe Runner do
  describe 'Running DSL scripts' do
    it_behaves_like 'script evaluation', './lib/contracts/using_bitcoin_script.rb'

    it_behaves_like 'script evaluation', './lib/contracts/anchor_transactions.rb'
    it_behaves_like 'script evaluation', './lib/contracts/fold_transactions.rb'
    it_behaves_like 'script evaluation', './lib/contracts/multisig.rb'
    it_behaves_like 'script evaluation', './lib/contracts/simple.rb'
  end

  describe 'Running ARK contracts' do
    it_behaves_like 'script evaluation', './lib/contracts/ark/setup.rb'
    it_behaves_like 'script evaluation', './lib/contracts/ark/spend_cooperatively.rb'
    it_behaves_like 'script evaluation', './lib/contracts/ark/spend_unilateral.rb'
  end

  describe 'Running coinbases addresses' do
    it_behaves_like 'script evaluation', './lib/contracts/coinbase_with_policy.rb'
    it_behaves_like 'script evaluation', './lib/contracts/coinbase_with_descriptor.rb'
  end

  describe 'Running contracts with CSV and CLTV' do
    it_behaves_like 'script evaluation', './lib/contracts/csv.rb'
    it_behaves_like 'script evaluation', './lib/contracts/cltv.rb'
  end

  describe 'Running lightning contracts' do
    it_behaves_like 'script evaluation', './lib/contracts/lightning/funding.rb'
    it_behaves_like 'script evaluation', './lib/contracts/lightning/commitment_without_htlcs.rb'
    it_behaves_like 'script evaluation', './lib/contracts/lightning/close_cooperatively_without_htlcs.rb'
    it_behaves_like 'script evaluation', './lib/contracts/lightning/close_unilaterally_without_htlcs.rb'

    it_behaves_like 'script evaluation', './lib/contracts/lightning/add_htlc.rb'
    it_behaves_like 'script evaluation', './lib/contracts/lightning/local_close_unilaterally__remote_sweeps_pending_htlc_using_revocation_key.rb'
    it_behaves_like 'script evaluation', './lib/contracts/lightning/local_close_unilaterally__remote_sweeps_pending_htlc_using_preimage.rb'
  end
end
