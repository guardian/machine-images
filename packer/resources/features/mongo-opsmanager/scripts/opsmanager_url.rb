#!/usr/bin/env ruby
require 'aws-sdk'
require_relative 'locksmith/dynamo_db'
require_relative 'mongodb/rs_config'
require_relative 'aws/helpers'

Aws.config[:credentials] = Aws::InstanceProfileCredentials.new
Aws.config[:region] = AwsHelper::Metadata::region

locksmith = Locksmith::DynamoDB.new(
  lock_table_name = "mongo-initialisation",
  max_attempts = 240,
  lock_retry_time = 10,
  ttl = 3600
)

replica_set_config = MongoDB::ReplicaSetConfig.new

locksmith.lock(replica_set_config.key) do
  ops_manager_data = replica_set_config.ops_manager_data
  puts ops_manager_data['BaseUrl']
end
