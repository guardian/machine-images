module Locksmith
  module Log
    extend self

    def log(data)
      result = nil
      data = {lib: "locksmith"}.merge(data)
      if block_given?
        start = Time.now
        result = yield
        data.merge(elapsed: Time.now - start)
      end
      data.reduce(out=String.new) do |s, tup|
        s << [tup.first, tup.last].join("=") << " "
      end
      puts(out) if ENV["DEBUG"]
      return result
    end

  end
end
