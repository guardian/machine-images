require 'logger'
require 'syslog'
require 'singleton'

module Util
  class SingletonLogger
    include Singleton

    attr_accessor :logger

    def initialize
      # if nothing better comes along, log to STDERR
      @logger = Logger.new(STDERR)
    end

    def init_syslog(ident, facility, quiet_mode=false)
      ## Set up the sys logger.
      #  If quiet_mode is true then we only log to syslog
      #   Otherwise we log to both STDERR and syslog
      log_opt = Syslog::LOG_PID | Syslog::LOG_NDELAY

      if quiet_mode
        log_mask = Syslog::LOG_INFO
      else
        log_opt = log_opt | Syslog::LOG_PERROR
        log_mask = Syslog::LOG_DEBUG
      end

      logger = Syslog.open(ident = ident, log_opt = log_opt, facility = facility)
      logger.mask = Syslog::LOG_UPTO(log_mask)
      @logger = logger
    end
  end

  module LoggerMixin
    def logger
      Util::SingletonLogger.instance.logger
    end
  end
end