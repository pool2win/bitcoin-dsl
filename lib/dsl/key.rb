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

# DSL module for handle bitcoin keys
module Key
  def key(params = {})
    if params.is_a?(Hash) && params.include?(:wif)
      Bitcoin::Key.from_wif params[:wif]
    else
      Bitcoin::Key.generate
    end
  end

  def tweak_public_key(key, with:)
    Bitcoin::Taproot.tweak_public_key(Bitcoin::Key.from_xonly_pubkey(key.xonly_pubkey), with)
  end

  def tweak_private_key(key, with:)
    Bitcoin::Taproot.tweak_private_key(key, with)
  end

  def sign_message_with_key(message:, key:)
    key.sign(message, algo: :schnorr)
  end

  def verify_signature_using_key(sig:, message:, key:)
    key.verify(sig, message, algo: :schnorr)
  end
end
