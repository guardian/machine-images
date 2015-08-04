# A class that encapsulates locking using a dynamo DB table
# Taken from http://r.32k.io/locking-with-dynamodb and the source code
# at https://github.com/bgentry/lock-smith
require 'thread'
require_relative './log'

module Locksmith
  class Dynamodb
    TTL = 120
    MAX_LOCK_ATTEMPTS = 20
    LOCK_TIMEOUT = 15
    LOCK_RETRY_TIME = 0.5

    def initialize(lock_table_name,
        ttl = TTL,
        max_attempts = MAX_LOCK_ATTEMPTS,
        lock_timeout = LOCK_TIMEOUT,
        lock_retry_time = LOCK_RETRY_TIME)
      @dynamo_lock = Mutex.new
      @lock_table_name = lock_table_name
      @ttl = ttl
      @max_attempts = max_attempts
      @lock_timeout = lock_timeout
      @lock_retry_time = lock_retry_time
      ensure_table_exists
    end

    def lock(name)
      attempts = 0
      while attempts < @max_attempts
        lock = fetch_lock(name)
        last_rev = lock["Locked"] || 0
        new_rev = Time.now.to_i
        log(at: "attempting", lock: name, lock: lock, rev: new_rev, attempt: attempts)
        begin
          Timeout::timeout(@lock_timeout) do
            release_lock(name, last_rev) if last_rev < (Time.now.to_i - @ttl)
            write_lock(name, 0, new_rev)
            log(at: "lock-acquired", lock: name, rev: new_rev)
            result = yield
            release_lock(name, new_rev)
            log(at: "lock-released", lock: name, rev: new_rev)
            return result
          end
        rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException
          log(at: "conditional_failed", lock: name)
          attempts += 1
        rescue Timeout::Error
          attempts += 1
          begin
            release_lock(name, new_rev)
          rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException
          end
          log(at: "timeout-lock-released", lock: name, rev: new_rev)
        end
        sleep(@lock_retry_time)
      end
    end

    def write_lock(name, rev, new_rev)
      update_lock_record(name, rev, new_rev)
    end

    def release_lock(name, rev)
      update_lock_record(name, rev, 0)
    end

    def update_lock_record(name, rev, new_rev)
      dynamo.update_item(
        :table_name => @lock_table_name,
        :key => { LockName: name },
        :update_expression => "SET Locked = :new_rev",
        :condition_expression => "Locked = :rev",
        :expression_attribute_values => { ":rev" => rev, ":new_rev" => new_rev }
      )
    end

    def fetch_lock(name)
      lock_record = dynamo.get_item(
        :table_name => @lock_table_name,
        :key => { :LockName => name },
        :consistent_read => true,
      ).data.item

      if !lock_record.nil?
        # return the record
        lock_record
      else
        begin
          dynamo.put_item(
            :table_name => @lock_table_name,
            :item => { LockName: name, Locked: 0 },
            :expected => { "LockName" => { comparison_operator: "NULL" } }
          )
          puts "added default record"
        rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException
          puts "record exists"
        end
        fetch_lock(name)
      end
    end

    def ensure_table_exists
      ## Create the table if it doesn't exist
      begin
        dynamo.describe_table(:table_name => @lock_table_name)
      rescue Aws::DynamoDB::Errors::ResourceNotFoundException
        dynamo.create_table(
          :table_name => @lock_table_name,
          :attribute_definitions => [
            {
              :attribute_name => :LockName,
              :attribute_type => :S
            }
          ],
          :key_schema => [
            {
              :attribute_name => :LockName,
              :key_type => :HASH
            }
          ],
          :provisioned_throughput => {
            :read_capacity_units => 1,
            :write_capacity_units => 1,
          }
        )

        # wait for table to be created
        log(at: "ensure_table_exists", table: @lock_table_name, status: "waiting")
        dynamo.wait_until(:table_exists, table_name: @lock_table_name)
        log(at: "ensure_table_exists", table: @lock_table_name, status: "created")
      end
    end

    def dynamo
      @dynamo_lock.synchronize do
        @db ||= Aws::DynamoDB::Client.new
      end
    end

    def log(data, &blk)
      Log.log({ns: "dynamo-lock"}.merge(data), &blk)
    end

  end
end
