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
