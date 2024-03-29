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

require_relative 'commands'
require_relative 'dsl'
require_relative 'node'

require 'singleton'
require 'test/unit/assertions'

# Runner interprets the bitcoin DSL using instance_eval
class Runner
  include Singleton
  include Test::Unit::Assertions
  include DSL

  def initialize
    @txid_signers = {}
    @witness_scripts = {}
    @coinbases = Hash.new { |h, k| h[k] = [] }
  end

  # Use method missing to invoke bitcoin RPC commands
  def method_missing(method, *args, &_block)
    if COMMANDS.include? method
      node method, *args
    else
      super
    end
  end

  def respond_to_missing?(method, *)
    COMMANDS.include? method or BITCOIN_HASHES.include? method
  end

  def run(file)
    @contract_file = file
    node :start
    begin
      run_script file
    ensure
      node :stop
    end
  end

  def run_script(file)
    contents = File.read(File.join(File.dirname(@contract_file), File.basename(file)))
    instance_eval contents, __FILE__, __LINE__
  end

  def log(message)
    if message.respond_to? :to_h
      logger.info JSON.pretty_generate message.to_h
    else
      logger.info message
    end
  end
end
