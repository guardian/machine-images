#!/usr/bin/env ruby
require 'ostruct'
require 'optparse'
require 'erb'
require 'base64'
require 'aws-sdk'
require_relative 'locksmith/dynamo_db'
require_relative 'aws/helpers'
require_relative 'mongodb/ops_manager_config'

options = OpenStruct.new
options.etcDir='/etc'
OptionParser.new do |opts|
  opts.banner = 'Usage: server_configure.rb [options]'
  opts.separator ''

  opts.on('--upstartTemplate TEMPLATE', 'Path to upstart template') do |upstart_template_file|
    options.upstart_template_file = upstart_template_file
  end
  opts.on('--mongoTemplate TEMPLATE', 'Path to mongo config template') do |mongo_config_template_file|
    options.mongo_config_template_file = mongo_config_template_file
  end

  opts.on('--etcDir [DIR]', 'Path to /etc (defaults to /etc)') do |etcDir|
    options.etcDir = etcDir
  end
end.parse!

def setup_mongod(name, port)
  @name = name
  @port = port
  upstart_template = ERB.new(File.read(options.upstart_template_file))
  File.write("#{options.etcDir}/init/mongod-#{@name}.conf", upstart_template.result)

  mongo_config_template = ERB.new(File.read(options.mongo_config_template_file))
  File.write("#{options.etcDir}/mongod-#{@name}.conf", mongo_config_template.result)
end

Aws.config[:credentials] = Aws::InstanceProfileCredentials.new
Aws.config[:region] = AwsHelper::Metadata::region

locksmith = Locksmith::DynamoDB.new(
  lock_table_name = "mongo-initialisation",
  max_attempts = 240,
  lock_retry_time = 10,
  ttl = 3600
)

config = MongoDB::OpsManagerConfig.new

locksmith.lock(config.key) do
  data = config.ops_manager_data
  if options.upstart_template_file && options.mongo_config_template_file
    setup_mongod('application', 27017)
    setup_mongod('blockstore', 27018)
  end
  gen_key = Base64.decode(data['GenKey'])
  File.write("#{options.etcDir}/mongodb-mms/gen.key", gen_key)
end
