# frozen_string_literal: false

require 'active_support/core_ext/hash/indifferent_access'
require 'optparse'
require 'test/unit'
require_relative 'node'
require_relative 'dsl'
require_relative 'commands'

ALICE_WIF = 'cRqVmDbyhw8kA9fWnAVJZDng3uTHfb71ELfpa8HBpTmkqLB2sA7f'
ASP_WIF = 'cQQ4UPzo6css6cFMEMjmfz5mNXcDanYff6yLo8yCbJHj1ESW1Qnp'

options = {}
OptionParser.new do |opt|
  opt.on('-s', '--script SCRIPT', 'Script to run') { |s| options[:script] = s }
end.parse!

unless options.include? :script
  puts 'No script provided. Exitting.'
  exit
end

puts "Running script from #{options[:script]}"

# Runner interprets the bitcoin DSL using instance_eval
class Runner
  include Test::Unit::Assertions
  include DSL

  def initialize
    @txid_signers = {}
    @witness_scripts = Hash.new { |h, k| h[k] = {} }
    @coinbases = Hash.new { |h, k| h[k] = [] }
  end

  # Use method missing to invoke bitcoin RPC commands
  def method_missing(method, *args, &_block)
    if COMMANDS.include? method
      node method, *args
    elsif BITCOIN_HASHES.include? method
      Bitcoin.send method, *args
    else
      super
    end
  end

  def respond_to_missing?(method, *)
    COMMANDS.include? method or BITCOIN_HASHES.include? method
  end

  def run(file)
    contents = File.read file
    instance_eval contents
  end

  def log(message)
    if message.respond_to? :to_h
      logger.info JSON.pretty_generate message.to_h
    else
      logger.info message
    end
  end
end

node :start
begin
  contents = File.read options[:script]
  runner = Runner.new
  runner.instance_eval contents, __FILE__, __LINE__
ensure
  node :stop
end
