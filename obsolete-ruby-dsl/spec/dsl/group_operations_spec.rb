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
require_relative '../../lib/dsl/group_operations'
require_relative '../../lib/dsl/key'
require_relative '../../lib/dsl/util'

RSpec.describe GroupOperations do
  include Key
  include GroupOperations
  include Util

  before(:context) do
    @key = key :new
    @other_key = key :new
    @scalar = '6af9e28dbf9d6aaf027696e2598a5b3d056f5fd2355a7fd5a37a0e5008132d30'
  end

  describe 'multiply key with hex string' do
    it 'should multiply without error' do
      expect(
        multiply(point: @key, scalar: @scalar).class
      ).to be ECDSA::Point
    end
  end

  describe 'multiply key with key' do
    it 'should multiply pubkey point with privkey integer' do
      expect(
        multiply(point: @key, scalar: @other_key)
      ).to eq(@key.to_point.multiply_by_scalar(@other_key.priv_key.to_i(16)))
    end
  end

  describe 'multiplying point and scalar' do
    it 'should be commutative' do
      expect(
        multiply(point: @key, scalar: @other_key)
      ).to eq(multiply(point: @other_key, scalar: @key))
    end

    it 'should be commutative when hashed' do
      expect(
        hash160(multiply(point: @key, scalar: @other_key))
      ).to eq(hash160(multiply(point: @other_key, scalar: @key)))
    end
  end
end
