# frozen_string_literal: false
require 'logger'

# Logging mixin to include in classes
module Logging
  # This is the magical bit that gets mixed into your classes
  def logger
    Logging.logger
  end

  # Global, memoized, lazy initialized instance of a logger
  def self.logger
    @logger ||= Logger.new($stdout)
    @logger.level = Logger::INFO
    @logger
  end
end
