# frozen_string_literal: false

require 'bitcoin'
require 'open3'
require 'ostruct'
require_relative 'logging'
require_relative 'dsl/broadcast'
require_relative 'dsl/key'
require_relative 'dsl/transaction'
require_relative 'dsl/query_node'
require_relative 'dsl/miniscript'

SATS = 100_000_000

# All the DSL supported functions that are not part of RPC API, go here.
module DSL
  include Logging
  include Key
  include Transaction
  include QueryNode
  include Miniscript
  include Broadcast

  def pretty_print(result)
    JSON.pretty_generate result
  end
end
