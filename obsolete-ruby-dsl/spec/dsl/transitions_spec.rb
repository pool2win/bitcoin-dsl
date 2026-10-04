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

require 'bitcoin'
require_relative '../../lib/dsl/transitions'

RSpec.describe Transitions do
  include Transitions

  describe 'init transitions' do
    it 'should have reset transition' do
      expect(Transitions.class_variable_get(:@@transitions).include?(:reset)).to be_truthy
    end
  end

  describe 'adding transitions' do
    it 'add transition' do
      transition :test do
        100
      end
      transition :test2 do
        100
      end
      expect(Transitions.class_variable_get(:@@transitions).include?(:test)).to be_truthy
      expect(Transitions.class_variable_get(:@@transitions).include?(:test2)).to be_truthy
    end
  end

  describe 'running transitions' do
    it 'runs an added transition' do
      test_flag = false
      test_flag2 = false
      transition :test_transition do
        test_flag = true
      end
      transition 'test second transition' do
        test_flag2 = true
      end
      run_transitions(:test_transition)
      expect(test_flag).to be_truthy
      expect(test_flag2).to be_falsey
      run_transitions 'test second transition'
      expect(test_flag).to be_truthy
      expect(test_flag2).to be_truthy
    end
  end
end
