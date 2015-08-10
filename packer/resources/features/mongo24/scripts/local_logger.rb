class LocalLogger
  def debug(msg)
    puts "DEBUG: #{msg}"
  end

  def info(msg)
    puts "INFO:  #{msg}"
  end

  def warn(msg)
    puts "WARN:  #{msg}"
  end

  def error(msg)
    puts "ERROR: #{msg}"
  end
end
