# frozen_string_literal: false

require_relative 'logging'

# Compile miniscript syntax to simple Script
class Miniscript
  include Logging

  def execute(script)
    script.gsub!('and', '_and')
    script.gsub!('or', '_or')
    instance_eval(script)
  end

  def _and(first, second)
    logger.debug "In and #{first} ... #{second}"
    "#{first} #{second} OP_AND"
  end

  def _or(first, second)
    logger.debug "In or #{first} ... #{second}"
    "#{first} #{second} OP_OR"
  end

  def older(val)
    logger.debug "In older #{val}"
    "#{val} OP_CHECKSEQUENCEVERIFY"
  end

  def pk(key)
    logger.debug "In pk #{key}"
    "#{key} OP_CHECKSIG"
  end

  def pkh(key)
    logger.debug "In pkh #{key}"
    "OP_DUP OP_HASH160 #{key} OP_EQUALVERIFY OP_CHECKSIG"
  end
end

ms = Miniscript.new

p ms.execute 'pk(:key_1)'

p ms.execute 'or(pk(:key_1),pk(:key_2))'

p ms.execute 'or(pk(:key_likely),pkh(:key_unlikely))'
