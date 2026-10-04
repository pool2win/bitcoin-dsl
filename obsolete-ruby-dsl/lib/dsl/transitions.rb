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

require_relative '../../lib/logging'

# DSL module for state transitions
module Transitions
  include Logging
  @@transitions = {} # We know we are setting module class variable.

  def transition(name, &block)
    @@transitions[name] = block
  end

  alias state_transition transition

  def run_transitions(*transitions)
    transitions.each do |transition|
      logger.info "Start #{transition}"
      @@transitions[transition].call
      logger.info "Finish #{transition}"
    end
  end

  def self.included(_mod)
    # Add a default reset state transition
    @@transitions[:reset] = proc {
      node :reset
    }
  end
end
