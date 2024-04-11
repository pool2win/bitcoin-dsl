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
require_relative '../../lib/dsl/key'

RSpec.describe Key do
  include Key

  before(:context) do
    @key = key wif: 'KztsFfy2uzazyo2zLgXneWH1U97Rv2dAiRQn74tR7qGMMYAjfGhD'
    @message = Bitcoin.sha256('message')
  end

  describe 'using key' do
    it 'should produce valid signatures' do
      sig = sign_message_with_key message: @message, key: @key
      expect(
        verify_signature_using_key(sig: sig, message: @message, key: @key)
      ).to be true
    end
  end

  describe 'using tweaked keys' do
    it 'should produce valid signatures' do
      tweak = '6af9e28dbf9d6aaf027696e2598a5b3d056f5fd2355a7fd5a37a0e5008132d30'
      public_key = tweak_public_key @key, with: tweak
      expect(public_key).to_not be nil
      private_key = tweak_private_key @key, with: tweak
      expect(private_key).to_not be nil

      sig = sign_message_with_key message: @message, key: private_key
      expect(verify_signature_using_key(sig: sig, message: @message, key: public_key)).to be true
    end
  end
end
