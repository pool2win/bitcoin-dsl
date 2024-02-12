# froze_string_literal: false

# DSL module for compiling miniscript output scripts
module Miniscript
  def compile_miniscript(script)
    policy = script.gsub!(/(\$)(\w+)/) { instance_eval("@#{Regexp.last_match(-1)}", __FILE__, __LINE__).pubkey }
    output = `miniscript-cli -m '#{policy}'`
    raise "Error parsing policy #{policy}" if output.empty?

    result = output.split("\n")
    logger.debug "Script: #{result[0]}"
    logger.debug "scriptpubkey: #{result[1]}"
    result[2].strip # return the Wsh wrapped descriptor
  end
end
