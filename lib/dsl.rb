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
require 'open3'
require 'ostruct'
require_relative 'logging'

require_relative 'dsl/tx'
require_relative 'dsl/broadcast'
require_relative 'dsl/compile_script'
require_relative 'dsl/key'
require_relative 'dsl/numbers'
require_relative 'dsl/query_node'
require_relative 'dsl/transaction'
require_relative 'dsl/anchor'
require_relative 'dsl/assertions'

# All the DSL supported functions that are not part of RPC API, go here.
module DSL
  include Logging
  include Key
  include Transaction
  include Anchor
  include Assertions
  include QueryNode
  include CompileScript
  include Broadcast

  def pretty_print(result)
    puts JSON.pretty_generate result
  end

  alias pp pretty_print
end
