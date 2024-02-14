# froze_string_literal: false

# DSL module for compiling miniscript and generating script sig
module CompileScript
  def compile_miniscript(script)
    policy = script.gsub!(/(\$)(\w+)/) { instance_eval("@#{Regexp.last_match(-1)}").pubkey }
    output = `miniscript-cli -m '#{policy}'`
    raise "Error parsing policy #{policy}" if output.empty?

    result = output.split("\n")
    logger.debug "Script: #{result[0]}"
    logger.debug "scriptpubkey: #{result[1]}"
    result[2].strip # return the Wsh wrapped descriptor
  end

  # Compile a scriptSig, replacing `sig:pk` with a signature by pk.
  # Return an array of components that will be concatenated into the witness stack
  def compile_script_sig(transaction, input, index, stack)
    input[:script_sig].scan(/(p2wpkh:)(\w+)/).each do |element|
      key = instance_eval("@#{element[1]}")
      stack << get_signature(transaction, input, index, key)
      stack << key.pubkey.htb
    end
  end

  # Parses address s.t. if there is a p2wpkh tag, we generate a corresponding address for the key.
  # If there are no tags in the address, we return the received address as it is.
  def parse_address(address)
    address.gsub(/(p2wpkh:)(\w+)/) { instance_eval("@#{Regexp.last_match(-1)}").to_p2wpkh }
  end
end
