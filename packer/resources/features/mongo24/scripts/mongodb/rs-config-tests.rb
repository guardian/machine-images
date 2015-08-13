#!/usr/bin/env ruby
# Test the locking code
require 'aws-sdk-core'
require_relative './rs_config'

# use credentials file at .aws/credentials
Aws.config[:credentials] = Aws::SharedCredentials.new
Aws.config[:region] = 'eu-west-1'

seed_list = MongoDB::ReplicaSetConfig.new('seedlist-testing', 'test-repl-set')

puts seed_list.seeds.join(', ')
sleep(2)
puts seed_list.add_seed('member1').join(', ')
sleep(2)
puts seed_list.add_seed('member2').join(', ')
sleep(2)
puts seed_list.remove_seed('memberX').join(', ')
sleep(2)
puts seed_list.add_seed('member3').join(', ')
sleep(2)
puts seed_list.add_seed('member3').join(', ')
sleep(2)
puts seed_list.remove_seed('member2').join(', ')
