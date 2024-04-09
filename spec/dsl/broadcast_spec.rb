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

require 'bitcoin'
require_relative '../../lib/dsl/broadcast'
require_relative '../../lib/dsl'
require_relative '../../lib/node'

RSpec.describe Broadcast do
  include DSL
  include Broadcast

  before(:context) do
    @key1 = Bitcoin::Key.generate
    @key2 = Bitcoin::Key.generate
  end

  before(:example) { node :reset }
  after(:example) { node :stop }

  describe 'Reorganising chain' do
    it 'should raise error if neither height not blockhash is provided' do
      expect { reorg_chain }.to raise_error('Provide height or blockhash to reorg')
    end
  end
end
