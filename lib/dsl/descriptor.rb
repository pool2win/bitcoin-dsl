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

# Descriptor module to work with Bitcoin::Key instances.
# Convert Key to pubkey string and then call Bitcoin::Descriptor
module Descriptor
  include Bitcoin::Descriptor

  def convert_key(key)
    if key.is_a?(Bitcoin::Key) && @taproot_context
      key.xonly_pubkey
    elsif key.is_a?(Bitcoin::Key) && !@taproot_context
      key.pubkey
    else
      key
    end
  end

  def convert_keys(keys)
    keys.map { |k| convert_key k}
  end

  def pk(key)
    key = convert_key key
    return super(key.pubkey) if key.is_a? Bitcoin::Key

    super key
  end

  def pkh(key)
    key = convert_key key
    return super(key.pubkey) if key.is_a? Bitcoin::Key

    super key
  end

  def wpkh(key)
    key = convert_key key
    return super(key.pubkey) if key.is_a? Bitcoin::Key

    super key
  end

  def wsh(script)
    script = descriptor_interpolate(script) if script.is_a?(String)

    super script
  end

  def sh(script)
    script = descriptor_interpolate(script) if script.is_a?(String)

    super script
  end

  def combo(key)
    key = convert_key key
    super key
  end

  def multi(threshold, *keys, sort: false)
    keys = convert_keys keys
    super threshold, *keys, sort: sort
  end

  def sortedmulti(threshold, *keys)
    keys = convert_keys keys
    super threshold, *keys
  end

  def descriptor_interpolate(script)
    Bitcoin::Script.from_string(script.split.collect { |e| instance_eval e }.join(' '))
  end
end
