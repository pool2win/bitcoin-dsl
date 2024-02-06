# frozen_string_literal: false

require 'optparse'
require_relative 'node'
require_relative 'key'

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
  # Use method missing to invoke bitcoin RPC commands
  def method_missing(method, *args, &_block)
    node method, *args
  end

  def respond_to_missing?(_method, *)
    true
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
