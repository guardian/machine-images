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
require_relative 'locksmith/dynamodb'
require_relative 'mongodb/repl_set'
require_relative 'mongodb/rs_config'
require_relative 'aws/helpers'

## Set sys logger facility
SYS_LOG_FACILITY = Syslog::LOG_LOCAL1

# Set up 'can not continue' exception class
class FatalError < StandardError
end

# Method to convert an 'availability zone visibility mask' from a string to a hash
# This is used to determine if a replica set member should be visible (not hidden)
# in a particular AZ.
# The string must be a distinct combination of letters (which should indicate AZs)
# An empty string represents 'not visible in all AZs'
def string_to_visibility_mask(visibility_mask_string = 'abc')
    visibility_mask_hash = Hash[visibility_mask_string.chars.map { |c| [c, true] }]
    visibility_mask_hash.default = false
    visibility_mask_hash
end

instance_tags = nil

def get_tag(tag_name)
  instance_tags ||= AwsHelper::InstanceData::get_tags
  instance_tags[tag_name]
end

def parse_options(args)
    # The options specified on the command line will be collected in *options*.
    # Set default values here.
    options = OpenStruct.new
    begin
        opts = OptionParser.new do |opts|

            opts.banner = "\nUsage: #{$0} [options]"

            opts.separator ""
            opts.separator "Specific options:"

            opts.on("-Z", "--zone_visibility_mask 'abc'",
            "AZ secondary member visibility mask (combination of a+b+c)") do |v|
                options.visibility_mask = string_to_visibility_mask(v)
            end
            opts.on("-D", "--debug", "Run in debug mode") do
                options.debug_mode = true
            end

            opts.on_tail("-h", "--help", "Show this message") do
                raise
            end

        end

        opts.parse!(args)

        raise "Non-empty list of arguments **(#{args})**" if !args.empty?

        options.debug_mode = options.debug_mode || false
        options.visibility_mask ||= string_to_visibility_mask("abc")

    rescue => e
        puts "\nOptions Error: #{e.message}" unless e.message.empty?
        puts opts
        puts
        exit
    end

    options

end  # parse_options()

def setup_logger(debug_mode=false)
    ## Set up the sys logger.
    #  If debug_mode is true, then we log to both STDERR and syslog.
    #  Otherwise we only log to syslog.
    logopt = Syslog::LOG_PID | Syslog::LOG_NDELAY

    if ! debug_mode
        logmask = Syslog::LOG_INFO
    else
        logopt = logopt | Syslog::LOG_PERROR
        logmask = Syslog::LOG_DEBUG
    end

    logger = Syslog.open(ident = $0, logopt = logopt, facility = SYS_LOG_FACILITY)
    logger.mask = Syslog::LOG_UPTO(logmask)
    return logger
end

# Method to initiate the replica set
# (essentially a wrapper for the 'replSetinitate' command).
def initiate(replica_set)
  config = replica_set.config

  if replica_set.replica_set?
    if replica_set.name != config.name
      raise FatalError, 'Member already belongs to a different Replica Set?!'
    else
      $logger.debug 'Mongodb Replica set already inititated...'
      return
    end
  end

  begin
    replica_set.initiate(false)
    replica_set.connect
  rescue Mongo::Error::OperationFailure => rinit
    $logger.debug 'Failed to initiate Replica Set...'
    $logger.debug rinit.message
    raise
  end
  $logger.debug 'Mongodb Replica set inititated...'
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
$logger = setup_logger(options.debug_mode)
$logger.info('MongoDB Add Replica Set Member.....')

availability_zone = AwsHelper::Metadata::availability_zone[-1..-1]
replica_set_config = MongoDB::ReplicaSetConfig.new

# Set up MongoDB replica set object
replica_set = MongoDB::ReplicaSet.new(replica_set_config)

locksmith = Locksmith::Dynamodb.new(
  lock_table_name = "mongo-initialisation",
  max_attempts = 240,
  lock_retry_time = 10,
  ttl = 3600
)

lock_attempts = 0

# first of all, check that authentication has been set up on the local
# instance


locksmith.lock(replica_set_config.name) do
  # lock taken using the replica set name
  rs_add_attempts = 0
  begin
    replica_set.connect
    seed_list = replica_set_config.seeds

    if seed_list.empty?
    then
      ## Assume from this point on that we may need to initiate the replica set
      ## but only if the seed list is empty which implies the replica set has not
      ## been deployed before.
      $logger.debug('WARNING: Host Seed List is empty....initiating Replica Set!')
      initiate(replica_set)
      $logger.debug('Replica Set inititated')

      # Add Admin User account if not already added.
      if !replica_set.authed?
      then
        $logger.debug('Adding admin user....')
        begin
          replica_set.create_admin_user()
          $logger.debug('Admin user added.')
        rescue => e
          $logger.debug('Failed to add admin user.')
          $logger.debug(e.message)
          raise
        end
      end
    else
      ## If this member hasn't been added (in case when replica set had already
      #  been inititated) then add it now
      replica_set.add_this_host(options.visibility_mask[availability_zone]) \
          unless replica_set.member?(replica_set.this_host_key)
    end

    # Add the member to the seed list.
    $logger.debug("Ensuring #{replica_set.this_host_key} is in seed list")
    replica_set_config.add_seed(replica_set.this_host_key)

    # By now it should be possible to connect directly to the replica set
    # This serves as an assertion that the member has been added successfully
    replica_set.connect
    raise FatalError, 'Could not connect to newly configured Replica Set' \
        unless replica_set.replica_set?

    # Delete any members in the seed list which are no longer in the replica set config
    if replica_set.replica_set_connection?
      all_members = replica_set.member_names
      ghost_members = replica_set_config.seeds.reject { |m| all_members.include?(m) }
      ghost_members.each { |g|
        $logger.debug("Removing #{g} from seed list")
        replica_set_config.remove_seed(g)
      }
    }

    # Attempt to reconfigure the replica set again for a few times unless a fatal error occurs
    rescue FatalError => fe
      $logger.debug("FATAL Error. Cannot continue:")
      $logger.debug("#{fe.message}")
      raise
    rescue => ce
      if (rs_add_attempts += 1) < MongoDB::REPLSET_RECONFIG_MAX_ATTEMPTS
      then
        $logger.debug('Failed to add MongoDB Replica Set Member.....'+
            "(attempt = #{rs_add_attempts})")
        $logger.debug("#{ce.message}")
        $logger.debug("Sleeping for #{MongoDB::REPLSET_CONNECT_WAIT} seconds.....")
        sleep(MongoDB::REPLSET_CONNECT_WAIT)
        retry
      end
      $logger.info("FAILED: #{ce.message}")
      $logger.info("EXITING...")
      raise
    end
end

$logger.info('MongoDB Add Replica Set Member COMPLETE!')

exit
