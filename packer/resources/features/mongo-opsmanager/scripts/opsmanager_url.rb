#!/usr/bin/env ruby
require 'aws-sdk'
require_relative 'locksmith/dynamo_db'
require_relative 'mongodb/rs_config'
require_relative 'aws/helpers'
require 'optparse'
require 'ostruct'

options = OpenStruct.new
OptionParser.new do |opts|
  opts.banner = 'Usage: agent_configure.rb [options]'
  opts.separator ''

  opts.on('-a', '--app app', 'App of the database') do |app|
    options.app = app
  end
end.parse!

Aws.config[:credentials] = Aws::InstanceProfileCredentials.new
Aws.config[:region] = AwsHelper::Metadata::region

locksmith = Locksmith::DynamoDB.new(
  lock_table_name = "mongo-initialisation",
  max_attempts = 240,
  lock_retry_time = 10,
  ttl = 3600
)

if options.app
  tags = AwsHelper::InstanceData::get_tags
  rs_key = [tags['Stack'], options.app, tags['Stage']].join('-')
  replica_set_config = MongoDB::ReplicaSetConfig.new(nil, rs_key)
else
  replica_set_config = MongoDB::ReplicaSetConfig.new
end

locksmith.lock(replica_set_config.key) do
  ops_manager_data = replica_set_config.ops_manager_data
  puts ops_manager_data['BaseUrl']
end
