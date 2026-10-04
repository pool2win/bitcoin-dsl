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

# DSL module for handle group operations
module GroupOperations
  # If given a Bitcoin::Key convert to ECDSA::Point
  def to_point(point)
    case point
    when Bitcoin::Key
      point.to_point
    when ECDSA::Point
      point
    end
  end

  # If given a hex string convert to Integer
  def to_scalar(scalar)
    case scalar
    when String
      if scalar.encoding == Encoding::ASCII_8BIT
        scalar.bti
      else
        scalar.to_i(16)
      end
    when Bitcoin::Key
      scalar.priv_key.to_i(16)
    when Integer
      scalar
    end
  end

  # Multiply a point and a scalar
  # Point - a Bitcoin::Key or a ECDSA::Point
  # Scalar - a hex string or an int
  def multiply(point:, scalar:)
    point = to_point point
    scalar = to_scalar scalar
    point.multiply_by_scalar scalar
  end

  def generate_point_for(data)
    scalar = to_scalar data
    ECDSA::Group::Secp256k1.generator.multiply_by_scalar(scalar)
  end
end
