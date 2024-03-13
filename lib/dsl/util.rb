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

require_relative '../commands'

# Utility functions for use with DSL
module Util
  include Bitcoin::Util

  # Define all bitcoin hashes to take String or Bitcoin::Key
  # Anyone missing C++ method overriding? :)
  BITCOIN_HASHES.each do |hash_name|
    define_method(hash_name) do |arg|
      case arg
      when Bitcoin::Key
        arg.send(hash_name)
      else
        super arg
      end
    end
  end
end
