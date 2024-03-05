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
    it_behaves_like 'script evaluation', './lib/anchor_transactions.rb'
    it_behaves_like 'script evaluation', './lib/fold_transactions.rb'
    it_behaves_like 'script evaluation', './lib/multisig.rb'
    it_behaves_like 'script evaluation', './lib/simple.rb'

    it_behaves_like 'script evaluation', './lib/ark/setup.rb'
    it_behaves_like 'script evaluation', './lib/ark/spend_cooperatively.rb'
    it_behaves_like 'script evaluation', './lib/ark/spend_unilateral.rb'
  end
end
