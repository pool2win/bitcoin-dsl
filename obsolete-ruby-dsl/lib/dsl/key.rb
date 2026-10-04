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

# froze_string_literal: false

require_relative './group_operations'

# DSL module for handle bitcoin keys
module Key
  include GroupOperations

  def self.included(_mod)
    Bitcoin::Node::Configuration.new(network: :regtest)
  end

  def key(params = {})
    if params.is_a?(Hash)
      from_params(params)
    else
      Bitcoin::Key.generate
    end
  end

  def from_params(params)
    if params.include?(:wif)
      Bitcoin::Key.from_wif params[:wif]
    elsif params.include?(:from_point)
      Bitcoin::Key.from_point params[:from_point]
    elsif params.include?(:even_y)
      even_y
    end
  end

  def even_y
    generated = Bitcoin::Key.generate
    generated = Bitcoin::Key.generate until generated.to_point.has_even_y?
    generated
  end

  def point_from(key)
    key.to_point
  end

  def point_from_scalar(hex_value)
    ECDSA::Group::Secp256k1.generator.to_jacobian * hex_value.to_i(16)
  end

  def scalar_from(key)
    key.priv_key.to_i(16)
  end

  # Tweak a given public key with the supplied tweak
  def tweak_public_key(key, with:)
    tweak = generate_point_for(with)
    Bitcoin::Key.from_point(key.to_point + tweak)
  end

  # Tweak a given private key with the supplied tweak
  def tweak_private_key(key, with:)
    point = key.to_point
    private_key = point.has_even_y? ? key.priv_key.to_i(16) : ECDSA::Group::Secp256k1.order - key.priv_key.to_i(16)
    private_key = ECDSA::Format::IntegerOctetString.encode(
      (with.to_i(16) + private_key) % ECDSA::Group::Secp256k1.order, 32
    )
    Bitcoin::Key.new(priv_key: private_key.bth)
  end

  # Tweak the taproot output's internal key
  def tweaked_internal_key(transaction: nil, vout: nil)
    builder = builder_for(transaction: transaction, vout: vout)
    builder.tweak_public_key
  end

  # Tweak a given private key with taproot output's merkle root as tweak
  def tweaked_private_key(key, transaction: nil, vout: nil)
    builder = builder_for(transaction, vout)
    builder.tweak_private_key(key)
  end

  def builder_for(transaction:, vout:)
    return nil unless transaction && vout

    taproot = transaction.build_params[:outputs][vout][:taproot]
    builder = Bitcoin::Taproot::SimpleBuilder.new(taproot[:internal_key].xonly_pubkey, taproot[:leaves]).build
    builder.merkle_root
  end

  def sign_message_with_key(message:, key:)
    key.sign(message, algo: :schnorr)
  end

  def verify_signature_using_key(sig:, message:, key:)
    key.verify(sig, message, algo: :schnorr)
  end
end
