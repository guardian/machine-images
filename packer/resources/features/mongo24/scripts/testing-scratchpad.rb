#!/usr/bin/env ruby

require 'socket'
require 'aws-sdk'
require 'syslog'
require 'mongo'
require_relative 'mongodb/repl_set'
require_relative 'mongodb/rs_config'
require_relative './local_logger'

$logger = LocalLogger.new

# use credentials file at .aws/credentials (testing)
# Aws.config[:credentials] = Aws::SharedCredentials.new
# use instance profile (when on instance)
Aws.config[:credentials] = Aws::InstanceProfileCredentials.new
Aws.config[:region] = AwsHelper::Metadata::region

config = MongoDB::ReplicaSetConfig.new

replset = MongoDB::ReplicaSet.new(config)

@client = replset.connect

puts "authed? #{replset.authed?}"

@client.database.collections

puts "Cluster: #{@client.cluster}"
puts "Topology: #{@client.cluster.topology}" unless @client.cluster.nil?

if replset.nil?
  this_host_ip = IPSocket.getaddress(Socket.gethostname)

  init_config = {
      :_id => config.key,
      :members => [{ :_id => 0, :host => "#{this_host_ip}:27017" }]
  }

  @client.database.command(:replSetInitiate => init_config)
  puts 'sleeping'
  sleep(20)
end

puts "replset: #{replset.replica_set?}"

puts "status: #{replset.get_status}"
puts "members: #{replset.member_names}"
puts "member?: #{replset.member?('10.248.203.230:27017')}"
