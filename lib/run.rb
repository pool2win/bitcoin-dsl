# frozen_string_literal: false

require 'optparse'
require 'test/unit'
require_relative 'node'
require_relative 'key'
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
  # Use method missing to invoke bitcoin RPC commands
  def method_missing(method, *args, &_block)
    if COMMANDS.include? method
      node method, *args
    elsif BITCOIN_HASHES.include? :method
      Bitcoin.send method, *args
    else
      super
    end
  end

  def respond_to_missing?(method, *)
    COMMANDS.include? method or BITCOIN_HASHES.include? method
  end
end

node :start
begin
  contents = File.read options[:script]
  runner = Runner.new
  runner.instance_eval contents
ensure
  node :stop
end
