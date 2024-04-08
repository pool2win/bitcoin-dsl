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

# Functions to read script data from 
module ScriptDataReader
  # Return all consecutive pushdata elements in script available from start index onwards.
  #
  # If none available, then return empty collection
  def all_pushdata(transaction:, vout:, start: 0)
    all_pushdata_from_script(from: transaction.outputs[vout].script_pubkey, start: start)
  end

  def all_pushdata_from_script(from:, start: 0)
    from.chunks[start..].take_while(&:pushdata?).map(&:pushed_data)
  end
end
