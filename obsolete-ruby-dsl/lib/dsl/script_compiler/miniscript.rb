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
    def miniscript_interpolate(script)
      script.gsub(/(?<!\d)@\w+/) do
        obj = instance_eval(Regexp.last_match(0), __FILE__, __LINE__)
        case obj
        when Bitcoin::Key
          obj.pubkey
        else
          obj
        end
      end
    end

    def compile_miniscript(script)
      policy = miniscript_interpolate(script)
      output = `miniscript-cli -m '#{policy}'`
      raise "Error parsing policy #{policy}" if output.empty?

      result = JSON.parse(output)
      witness_script = Bitcoin::Script.parse_from_payload(result['witness_script'].htb)
      logger.info "Provided miniscript #{script}, compiled to following: \n #{witness_script}"
      # return the Wsh wrapped descriptor and the witness script
      store_witness(result['address'], witness_script)
      [Bitcoin::Script.parse_from_addr(result['address']), witness_script]
    end

    def compile_descriptor(descriptor)
      parsed = descriptor_interpolate(descriptor)
      address = parsed.to_addr
      if descriptor.start_with? 'wsh'
        witness = descriptor.match(/wsh\((.*)\)/)[1]
        witness_script = descriptor_interpolate(witness)
        # return the Wsh wrapped descriptor and the witness script
        store_witness(address, witness_script)
      end
      [parsed, witness_script, address]
    end
  end
end
