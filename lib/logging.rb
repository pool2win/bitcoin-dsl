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

    log_level = ENV.fetch('LOG_LEVEL', 'INFO')
    @logger.level = Logger.const_get(log_level)
    @logger
  end
end
