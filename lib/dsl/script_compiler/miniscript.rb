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

# Script compiler module
module ScriptCompiler
  # Miniscript compiler
  module Miniscript
    def compile_miniscript(script)
      policy = script.gsub!(/(\$)(\w+)/) { instance_eval("@#{Regexp.last_match(-1)}", __FILE__, __LINE__).pubkey }
      output = `miniscript-cli -m '#{policy}'`
      raise "Error parsing policy #{policy}" if output.empty?

      result = output.split("\n")
      logger.debug "Result: #{result}"
      compiled_script = Bitcoin::Script.parse_from_payload(result[1].htb)
      # return the Wsh wrapped descriptor and the witness script
      [Bitcoin::Script.parse_from_addr(result[0]), compiled_script]
    end
  end
end
