# A class that encapsulates locking using a dynamo DB table
# Taken from http://r.32k.io/locking-with-dynamodb and the source code
# at https://github.com/bgentry/lock-smith
require 'thread'
require 'locksmith/config'
require 'locksmith/log'

module Locksmith
  module Dynamodb
    extend self
    TTL = 60
    MAX_LOCK_ATTEMPTS = 3
    LOCK_TIMEOUT = 30
    LOCK_TABLE = "Locks"

    @dynamo_lock = Mutex.new
    @table_lock = Mutex.new

    def lock(name)
      lock = fetch_lock(name)
      last_rev = lock[:Locked] || 0
      new_rev = Time.now.to_i
      attempts = 0
      while attempts < MAX_LOCK_ATTEMPTS
        begin
          Timeout::timeout(LOCK_TIMEOUT) do
            release_lock(name, last_rev) if last_rev < (Time.now.to_i - TTL)
            write_lock(name, 0, new_rev)
            log(at: "lock-acquired", lock: name, rev: new_rev)
            result = yield
            release_lock(name, new_rev)
            log(at: "lock-released", lock: name, rev: new_rev)
            return result
          end
        rescue AWS::DynamoDB::Errors::ConditionalCheckFailedException
          attempts += 1
        rescue Timeout::Error
          attempts += 1
          begin
            release_lock(name, new_rev)
          rescue AWS::DynamoDB::Errors::ConditionalCheckFailedException
          end
          log(at: "timeout-lock-released", lock: name, rev: new_rev)
        end
      end
    end

    def write_lock(name, rev, new_rev)
      locks.put({Name: name, Locked: new_rev},
        :if => {:Locked => rev})
    end

    def release_lock(name, rev)
      locks[name].delete(:if => {:Locked => rev})
    end

    def fetch_lock(name)
      if locks.at(name).exists?(consistent_read: true)
        locks[name].attributes.to_h(consistent_read: true)
      else
        locks.put(Name: name, Locked: 0).attributes.to_h(consistent_read: true)
      end
    end

    def locks
      table(LOCK_TABLE)
    end

    def table(name)
      @table_lock.synchronize {tables[name].items}
    end

    def tables
      @tables ||= dynamo.tables.
        map {|t| t.load_schema}.
        reduce({}) {|h, t| h[t.name] = t; h}
    end

    def dynamo
      @dynamo_lock.synchronize do
        @db ||= AWS::DynamoDB.new(access_key_id: Config.aws_id,
                                   secret_access_key: Config.aws_secret)
      end
    end

    def log(data, &blk)
      Log.log({ns: "dynamo-lock"}.merge(data), &blk)
    end

  end
end
