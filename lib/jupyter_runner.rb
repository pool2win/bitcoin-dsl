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

# This is a monkey patch for the IRuby PlainBackend. The patch changes
# the binding to the BitcoinDSL's Runner class.
module IRuby
  class PlainBackend
    def initialize
      puts "CUSTOM ....."
      require 'irb'
      require 'irb/completion'

      require_relative './runner'
      runner = Runner.new
      IRB.setup(nil)
      @main = runner
      init_main_object(@main)
      @workspace = IRB::WorkSpace.new(@main)
      @irb = IRB::Irb.new(@workspace)
      @eval_path = @irb.context.irb_path
      IRB.conf[:MAIN_CONTEXT] = @irb.context
    end

    # @private
    def shutdown_request(msg)
      node :stop
      @session.send(:reply, :shutdown_reply, msg[:content])
      @running = false
    end
  end
end
