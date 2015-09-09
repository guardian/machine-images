#!/usr/bin/env ruby
require 'ostruct'
require 'optparse'
require 'erb'
require 'aws-sdk'
require_relative 'locksmith/dynamo_db'
require_relative 'mongodb/rs_config'
require_relative 'aws/helpers'

options = OpenStruct.new
OptionParser.new do |opts|
  opts.banner = 'Usage: mongodb_configure.rb [options]'
  opts.separator ''

  opts.on('-k', '--keyFile KEYFILE', 'Path to write the keyfile') do |keyFilePath|
    options.keyFilePath = keyFilePath
  end

  opts.on('-c', '--configFile CONFIGFILE', 'Path to write the config file') do |configFilePath|
    options.configFilePath = configFilePath
  end

  opts.on('-t', '--template TEMPLATE', 'Path to config file template') do |templateFile|
    options.templateFile = templateFile
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

replica_set_config = MongoDB::ReplicaSetConfig.new

locksmith.lock(replica_set_config.key) do
  if options.keyFilePath
    security_data = replica_set_config.security_data
    # write out keyFile
    File.write(options.keyFilePath, security_data[:key])
  end
  if options.configFilePath && options.templateFile
    # write out mongodb.conf
    @replica_set_name = replica_set_config.name
    template = ERB.new(File.read(options.templateFile))
    File.write(options.configFilePath, template.result)
  end
end
