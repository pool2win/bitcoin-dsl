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
  tx = Bitcoin::Tx.new
  tx = add_inputs(tx, params) if params.include? :inputs
  tx = add_outputs(tx, params) if params.include? :outputs
  tx.version = params[:version] if params.include? :version
  add_signatures(tx, params) if params.include? :inputs
  tx
end

def add_inputs(tx, params)  
  tx
end

def add_outputs(tx, params)
  tx
end

def add_signatures(tx, params)
  tx
end
