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
require_relative '../../lib/dsl/descriptor'

RSpec.describe Descriptor do
  include Descriptor

  before(:context) do
    @key1 = Bitcoin::Key.generate
    @key2 = Bitcoin::Key.generate
  end

  describe 'Getting script from descriptor' do
    it 'should convert pk' do
      expect { pk @key1 }.not_to raise_error
    end
    it 'should convert pkh' do
      expect { pkh @key1 }.not_to raise_error
    end
    it 'should convert wpkh' do
      expect { wpkh @key1 }.not_to raise_error
    end
    it 'should convert combo' do
      expect { combo @key1 }.not_to raise_error
    end
    it 'should convert multi' do
      expect { multi 2, @key1, @key2 }.not_to raise_error
    end
    it 'should convert sortedmulti' do
      expect { sortedmulti 2, @key1, @key2 }.not_to raise_error
    end
  end
end
