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
require_relative 'aws/helpers'
require_relative 'util/logger'

## Set sys logger facility
SYS_LOG_FACILITY = Syslog::LOG_LOCAL1

# Set up 'can not continue' exception class
class FatalError < StandardError
end

def get_tag(tag_name)
  instance_tags ||= AwsHelper::InstanceData::get_custom_tags
  instance_tags[tag_name]
end

def get_identity_instances
  tags = AwsHelper::InstanceData::get_custom_tags
  AwsHelper::EC2::get_instances(tags)
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

      opts.on('-q', '--quiet', "Run in quiet mode (don't log to stderr") do
        options.quiet_mode = true
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


class MMS
  include HTTParty

  def initialize(mms_config)
    @mms_config = mms_config
    self.class.base_uri "#{@mms_config['BaseUrl']}/api/public/v1.0/groups/#{@mms_config['GroupId']}"
    self.class.digest_auth @mms_config['AutomationApiUser'], @mms_config['AutomationApiKey']
  end

  def automation_status
    self.class.get("/automationStatus")
  end

  def automation_config
    self.class.get("/automationConfig")
  end

  def put_automation_config(new_config)
    response = self.class.put(
      "/automationConfig",
      :body => new_config.to_json,
      :headers => { 'Content-Type' => 'application/json'}
    )
    if response.code >= 400
      raise FatalError, "API response code was #{response.code}: #{response.body}"
    end
    response
  end

  def hosts
    self.class.get("/hosts")
  end

  def delete_hosts(id)
    response = self.class.delete("/hosts/#{id}")
    if response.code >= 400
      raise FatalError, "API response code was #{response.code}: #{response.body}"
    end
    response
  end

  def automation_agents
    self.class.get("/agents/AUTOMATION")
  end

  def wait_for_goal_state
    logger.info 'Entering wait for goal state'
    hosts_to_check = automation_agents['results'].map{ |e| e['hostname'] }
    loop do
      status = automation_status
      goal = status['goalVersion']
      last_goals = status['processes'].select{ |e| hosts_to_check.include?(e['hostname']) }.map{|e| e['lastGoalVersionAchieved']}
      logger.info "Goal: #{goal} Last achieved: #{last_goals}"
      break if last_goals.all? { |e| goal == e }
      sleep 5
    end
    logger.info 'Successfully reached goal state'
  end
end

def save_json(data, filename)
  File.write(filename, JSON.pretty_generate(data))
end
## main

exit if __FILE__ != $0

# use credentials file at .aws/credentials (testing)
# Aws.config[:credentials] = Aws::SharedCredentials.new

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

logger.info('MongoDB: Configure Replica Set Member in MMS.....')

replica_set_config = MongoDB::ReplicaSetConfig.new

locksmith = Locksmith::DynamoDB.new(
    lock_table_name = 'mongo-initialisation',
    max_attempts = 240,
    lock_retry_time = 10,
    ttl = 3600
)

def set_version(mms, target)
  # Change the version of mongo
  config = mms.automation_config
  processes = config['processes']
  processes.each { |e| e['version'] = target }
  mms.put_automation_config(config)
  mms.wait_for_goal_state
end

def clean_up_dead_nodes(mms)
  # get the instances that we expect to be in the list
  mongo_nodes = get_identity_instances.map{|i| i.private_dns_name }
  logger.info "Known mongo nodes: #{mongo_nodes}"

  config = mms.automation_config
  save_json(config, 'cleanup-01.json')

  # find unknown processes
  unknown_processes = config['processes'].reject{|p| mongo_nodes.include?(p['hostname']) }
  if unknown_processes.length > 0
    unknown_names = unknown_processes.map{|p| p['name']}

    logger.info "Unknown process names: #{unknown_names}"

    # remove related process
    config['processes'].reject!{|p| unknown_processes.include?(p)}

    # remove related replicaSet members
    config['replicaSets'].each{|rs|
      rs['members'].reject!{|m|
        unknown_names.include?(m['host'])
      }
    }
    save_json(config, 'cleanup-02.json')

    mms.put_automation_config(config)
    mms.wait_for_goal_state
  end

  # find unknown hosts
  unknown_hosts = mms.hosts['results'].reject{|h| mongo_nodes.include?(h['hostname'])}
  # TODO - filter by the last seen date to ensure it really doesn't exist
  if unknown_hosts.length > 0
    logger.info "#{unknown_hosts.length}"
    logger.info "DELETE hosts: #{unknown_hosts.map{|h| h['hostname']}}"
    unknown_hosts.each{ |uh|
      mms.delete_hosts(uh['id'])
    }
  end
end

def add_self(mms)
  agents = mms.automation_agents
  this_host = agents['results'].find { |e| e['hostname'].include?(Socket.gethostname) }
  if this_host.nil?
    raise FatalError, 'This host does not have a registered automation agent'
  end

  config = mms.automation_config
  save_json(config, 'initial.json')
  processes = config['processes']
  this_process = processes.find { |e| e['hostname'] == this_host['hostname'] }
  if this_process.nil?
    new_node = processes[0].clone
    new_node['hostname'] = this_host['hostname']
    new_node['alias'] = IPSocket.getaddress(Socket.gethostname)
    new_node['name'] = Socket.gethostname
    processes << new_node

    replica_set_members = config['replicaSets'][0]['members']
    new_member = replica_set_members[0].clone
    new_member['host'] = new_node['name']
    new_member['_id'] = replica_set_members.map{|e| e['_id']}.max + 1
    replica_set_members << new_member

    logger.info "Adding #{this_host['hostname']} to processes list with config:"
    save_json(config, 'modified.json')
    mms.put_automation_config(config)
    mms.wait_for_goal_state
  else
    logger.info 'This host is already in the processes list, no work to do'
  end
end

locksmith.lock(replica_set_config.key) do
  mms_config = replica_set_config.mms_data
  mms = MMS.new(mms_config)
  clean_up_dead_nodes(mms)
  add_self(mms)
end

logger.info('MongoDB Configure Replica Set Member in MMS COMPLETE!')
