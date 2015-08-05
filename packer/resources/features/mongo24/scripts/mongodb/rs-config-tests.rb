#!/usr/bin/env ruby
# Test the locking code
require "aws-sdk-core"
require_relative "./rs_config"

# use credentials file at .aws/credentials
Aws.config[:credentials] = Aws::SharedCredentials.new
Aws.config[:region] = "eu-west-1"

seedlist = MongoDB::ReplicaSetConfig.new("seedlist-testing", "test-repl-set")

puts seedlist.seeds.join(", ")
sleep(2)
puts seedlist.add("member1").join(", ")
sleep(2)
puts seedlist.add("member2").join(", ")
sleep(2)
puts seedlist.remove("memberX").join(", ")
sleep(2)
puts seedlist.add("member3").join(", ")
sleep(2)
puts seedlist.add("member3").join(", ")
sleep(2)
puts seedlist.remove("member2").join(", ")
