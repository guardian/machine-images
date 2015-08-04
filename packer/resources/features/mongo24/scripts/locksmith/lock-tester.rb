#!/usr/bin/env ruby
# Test the locking code
require "aws-sdk-core"
require_relative "./dynamodb"

# use credentials file at .aws/credentials
Aws.config[:credentials] = Aws::SharedCredentials.new
Aws.config[:region] = "eu-west-1"

locksmith = Locksmith::Dynamodb.new("locksmith-testing")

while true do
  locksmith.lock("testing2") do
    puts "doing something in a lock"
    sleep(5)
    puts "releasing lock"
  end
  sleep(5)
end
