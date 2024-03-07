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

require_relative '../../dsl/util'

# Script compiler module
module ScriptCompiler
  # script pub key compiler
  module ScriptPubKey
    include Util

    def compile_script_pubkey(script)
      processed = script.split.collect do |element|
        instance_eval(element) || element
      end.join(' ')
      Bitcoin::Script.from_string processed
    end
  end
end
