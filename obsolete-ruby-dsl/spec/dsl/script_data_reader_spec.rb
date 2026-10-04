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
require_relative '../../lib/dsl/script_data_reader'

RSpec.describe 'all_pushdata' do
  include ScriptDataReader

  it 'should return all pushdata from script' do
    script = Bitcoin::Script.new << [1000, 2000]
    expect(all_pushdata_from_script(from: script)).to eq([
                                                           Bitcoin::Script.encode_number(1000).htb,
                                                           Bitcoin::Script.encode_number(2000).htb
                                                         ])
  end
end
