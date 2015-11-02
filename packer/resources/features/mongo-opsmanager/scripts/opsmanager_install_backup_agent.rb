#! /usr/bin/env ruby
#
# Script to automatically either initiate a MongoDB Replica set OR add the host on which the
# script is run to the replica set.
# The script is intended to be used by AWS Autoscaling Groups either to initiate an 'empty'
# replica set or add a member to an existing replica set
#
# NOTE: This script has been tested ONLY against:
#           MongoDB v2.4; ruby mongo driver v1.12.0; aws-sdk v1.63.0 and ruby v2.0.0p598.
#       The Ruby driver for this combined stack does not appear to properly return MongoDB server
#       error codes when an exception is raised by the server. The sript therefore relies
#       on parsing the error messages returned which may of course change in future versions
#       of either MongoDB or the other software used by this script.
#
require 'aws-sdk'
require 'syslog'
require 'optparse'
require 'ostruct'
require 'shellwords'
require 'httparty'
require 'socket'

require_relative 'locksmith/dynamo_db'
require_relative 'mongodb/rs_config'
require_relative 'mongodb/ops_manager'
require_relative 'aws/helpers'
require_relative 'util/logger'

## Set sys logger facility
SYS_LOG_FACILITY = Syslog::LOG_LOCAL1

# Set up 'can not continue' exception class
class FatalError < StandardError
end

def logger
  Util::SingletonLogger.instance.logger
end

def parse_options(args)
  # The options specified on the command line will be collected in *options*.
  # Set default values here.
  options = OpenStruct.new
  begin
    opts = OptionParser.new do |opts|

      opts.banner = "\nUsage: #{$0} [options]"

      opts.separator ''
      opts.separator 'Specific options:'

      opts.on('-q', '--quiet', "Run in quiet mode (don't log to stderr)") do
        options.quiet_mode = true
      end

      opts.on('-a', '--app [app]', 'App of the database') do |app|
        options.app = app
      end

      opts.on_tail('-h', '--help', 'Show this message') do
        raise
      end

    end

    opts.parse!(args)

    raise "Non-empty list of arguments **(#{args})**" unless args.empty?

    options.debug_mode ||= false

  rescue => e
    STDERR.puts "\nOptions Error: #{e.message}" unless e.message.empty?
    STDERR.puts opts
    STDERR.puts
    exit
  end

  options
end

def get_tag(tag_name)
  instance_tags ||= AwsHelper::InstanceData::get_custom_tags
  instance_tags[tag_name]
end

def get_identity_instances
  tags = AwsHelper::InstanceData::get_custom_tags
  AwsHelper::EC2::get_instances(tags)
end

## main
exit if __FILE__ != $0

# use instance profile (when on instance)
Aws.config[:credentials] = Aws::InstanceProfileCredentials.new
Aws.config[:region] = AwsHelper::Metadata::region

options = parse_options(ARGV)

# Set up global logger
Util::SingletonLogger.instance.init_syslog(
    ident = 'add_self_to_replset',
    facility = Syslog::LOG_LOCAL1,
    quiet_mode = options.quiet_mode
)

logger.info('MongoDB: Configure OpsManager backup agent.....')

tags = AwsHelper::InstanceData::get_tags
rs_key = [tags['Stack'], options.app, tags['Stage']].join('-')

replica_set_config = MongoDB::ReplicaSetConfig.new(nil, rs_key)

locksmith = Locksmith::DynamoDB.new(
    lock_table_name = 'mongo-initialisation',
    max_attempts = 240,
    lock_retry_time = 10,
    ttl = 3600
)

locksmith.lock(replica_set_config.key) do
  ops_manager_config = replica_set_config.ops_manager_data
  ops_manager = MongoDB::OpsManager.new(MongoDB::OpsManagerAPI.new(ops_manager_config))
  ops_manager.self_install_backup
end

logger.info('MongoDB: Configure OpsManager backup agent COMPLETE!')
