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
module CompileScript
  # script parse elements
  module ParseElement
    def parse_element(element)
      evaluated = instance_eval element
      evaluated = evaluated.is_a?(Bitcoin::Key) ? evaluated.pubkey : evaluated
      if opcode?(element)
        { type: :opcode, expression: element }
      elsif evaluated
        { type: :datum, expression: evaluated.htb }
      else
        raise "Unknown term in script sig #{element}"
      end
    end

    def as_opcode(name)
      Bitcoin::Opcodes.name_to_opcode(name)
    end

    def opcode?(name)
      !as_opcode(name).nil?
    end
  end
end
