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
require_relative '../../lib/dsl/util'

RSpec.describe Util do
  include Util

  before(:context) do
    @key = Bitcoin::Key.generate
  end

  describe 'hash160 should return hashes' do
    it 'should handle key' do
      expect(hash160(@key)).to be == @key.hash160
    end
    it 'should handle data' do
      expect(hash160('abcd')).to be == '4671c47a9d20c240a291661520d4af51df08fb0b'
    end
  end
end
