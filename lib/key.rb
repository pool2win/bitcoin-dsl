# frozen_string_literal: false

require 'bitcoin'

def key(params = {})
  if params.is_a?(Hash) && params.include?(:wif)
    Bitcoin::Key.from_wif params[:wif]
  else
    Bitcoin::Key.generate
  end
end

def transaction(params)
  Bitcoin::Tx.new
end
