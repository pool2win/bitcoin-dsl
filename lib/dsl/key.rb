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
end
