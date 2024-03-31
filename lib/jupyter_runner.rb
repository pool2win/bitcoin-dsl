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

require_relative 'runner'

IRuby::Kernel.events.register(:before_initialize) do
  IRuby.logger.warn 'Running before intialized'
  runner = Runner.instance
  IRuby::Kernel.custom_binding = runner
end

IRuby::Kernel.events.register(:initialized) do |_kernel|
  node :start
  IRuby.logger.info 'IRuby kernel has been initialized'
end

IRuby::Kernel.events.register(:before_shutdown) do |_kernel|
  node :stop
  IRuby.logger.info 'IRuby kernel is shutting down'
end
