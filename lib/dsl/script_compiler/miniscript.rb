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
    def interpolate(script)
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
      policy = interpolate(script)
      output = `miniscript-cli -m '#{policy}'`
      raise "Error parsing policy #{policy}" if output.empty?

      result = JSON.parse(output)
      witness_script = Bitcoin::Script.parse_from_payload(result['witness_script'].htb)
      # return the Wsh wrapped descriptor and the witness script
      store_witness(result['address'], witness_script)
      [Bitcoin::Script.parse_from_addr(result['address']), witness_script]
    end

    def compile_descriptor(descriptor)
      if descriptor.start_with?('tr(')
        compile_taproot_descriptor(descriptor)
      else
        compile_v0_descriptor(descriptor)
      end
    end

    def compile_v0_descriptor(descriptor)
      descriptor = interpolate(descriptor)
      output = `miniscript-cli -d '#{descriptor}'`
      raise "Error parsing descriptor #{descriptor}" if output.empty?

      result = JSON.parse(output)
      if descriptor.start_with? 'wsh'
        witness_script = Bitcoin::Script.parse_from_payload(result['witness_script'].htb)
        logger.debug "WITNESS SCRIPT #{witness_script}"
        # return the Wsh wrapped descriptor and the witness script
        store_witness(result['address'], witness_script)
      end
      [Bitcoin::Script.parse_from_addr(result['address']), witness_script, result['address']]
    end

    def compile_taproot_descriptor(descriptor)
      descriptor = interpolate(descriptor)
      output = `miniscript-cli -t '#{descriptor}'`
      raise "Error parsing descriptor #{descriptor}" if output.empty?

      result = JSON.parse(output)
      store_taproot(result)
      [Bitcoin::Script.parse_from_addr(result['address'])]
    end
  end
end
