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

require 'optparse'
require_relative 'runner'

ALICE_WIF = 'cRqVmDbyhw8kA9fWnAVJZDng3uTHfb71ELfpa8HBpTmkqLB2sA7f'.freeze
ASP_WIF = 'cQQ4UPzo6css6cFMEMjmfz5mNXcDanYff6yLo8yCbJHj1ESW1Qnp'.freeze

options = {}
OptionParser.new do |opt|
  opt.on('-s', '--script SCRIPT', 'Script to run') { |s| options[:script] = s }
end.parse!

unless options.include? :script
  puts 'No script provided. Exitting.'
  exit
end

puts "Running script from #{options[:script]}"

runner = Runner.instance
runner.run options[:script]
