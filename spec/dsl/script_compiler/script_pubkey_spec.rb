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
require_relative '../../../lib/dsl/script_compiler/script_pubkey'
require_relative '../../../lib/dsl'

RSpec.describe ScriptCompiler::ScriptPubKey do
  include DSL

  before(:context) do
    @witness_scripts = {}
  end

  describe 'Getting script from descriptor' do
    it 'should capture a integer as data' do
      @data = 100
      script = Bitcoin::Script.new
      script << 100
      expect(compile_script_pubkey('@data')[1]).to be == script
    end
    it 'should capture a string as data' do
      @data = '100'
      script = Bitcoin::Script.new
      script << '100'
      expect(compile_script_pubkey('@data')[1]).to be == script
    end
  end
end
