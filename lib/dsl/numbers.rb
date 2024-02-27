# frozen_string_literal: false

SATS = 100_000_000

# Add sats and other time keywords we need for bitcoin
class Numeric
  def sats
    self * SATS
  end
end
