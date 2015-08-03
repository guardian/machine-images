module Locksmith
  module Config
    extend self

    def env(key)
      ENV[key]
    end

    def env!(key)
      env(key) || raise("Locksmith is missing #{key}")
    end

    def env?(key)
      !env(key).nil?
    end

    def aws_id; env!("AWS_ID"); end
    def aws_secret; env!("AWS_SECRET"); end
  end
end
