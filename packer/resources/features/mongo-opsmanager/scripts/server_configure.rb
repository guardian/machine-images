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
options.ch_root=''
OptionParser.new do |opts|
  opts.banner = 'Usage: server_configure.rb [options]'
  opts.separator ''

  opts.on('--templateDir TEMPLATEDIR', 'Path to template directory') do |template_dir|
    options.template_dir = template_dir
  end

  opts.on('--chRoot [DIR]', 'Chroot for testing') do |ch_root|
    options.ch_root = ch_root
  end
end.parse!

def get_identity_instances
  tags = AwsHelper::InstanceData::get_custom_tags
  AwsHelper::EC2::get_instances(tags)
end

def setup_mongod(options, name, port)
  @name = name
  @port = port
  upstart_template = ERB.new(File.read("#{options.template_dir}/mongod.upstartconf.erb"))
  File.write("#{options.ch_root}/etc/init/mongod-#{@name}.conf", upstart_template.result)

  mongo_config_template = ERB.new(File.read("#{options.template_dir}/mongod.conf.erb"))
  File.write("#{options.ch_root}/etc/mongod-#{@name}.conf", mongo_config_template.result)
end

def setup_mms(options, data)
  @central_url = data['CentralUrl']
  @backup_central_url = data['BackupCentralUrl']
  @email_address = data['EmailAddress']

  known_hosts = get_identity_instances.map{|i| i.private_dns_name }
  mms_mongo_nodes = known_hosts.map{|h| "#{h}:27017"}
  @mongo_uri = "mongodb://#{mms_mongo_nodes.join(',')}"

  mms_template = ERB.new(File.read("#{options.template_dir}/conf-mms.properties.erb"))
  File.write("#{options.ch_root}/opt/mongodb/mms/conf/conf-mms.properties", mms_template.result)

  daemon_template = ERB.new(File.read("#{options.template_dir}/conf-daemon.properties.erb"))
  File.write("#{options.ch_root}/opt/mongodb/mms-backup-daemon/conf/conf-daemon.properties", daemon_template.result)
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
  setup_mongod(options, 'application', 27017)
  setup_mongod(options, 'blockstore', 27018)
  gen_key = Base64.decode64(data['GenKey'])
  File.write("#{options.etcDir}/mongodb-mms/gen.key", gen_key)
  setup_mms(options, data)
end
