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
require_relative 'mongodb/seed_list'
require_relative 'aws/helpers'

## Set sys logger facility
SYS_LOG_FACILITY = Syslog::LOG_LOCAL1

# Set up 'can not continue' exception class
class FatalError < StandardError
end

# Method to convert an 'avaiablitiy zone visibility mask' from a string to a hash
# This is used to determine if a replica set member should be visible (not hidden)
# in a particular AZ.
# The string must be a distinct combination of letters (which should indicate AZs)
# An empty string represents 'not visible in all AZs'
def string_to_visibility_mask(visibility_mask_string = 'abc')
    visibility_mask_hash = Hash[visibility_mask_string.chars.map { |c| [c, true] }]
    visibility_mask_hash.default = false
    visibility_mask_hash
end

def get_tag(tag_name)
  AwsHelper::InstanceData::get_tag(tag_name)
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

            opts.on("-s", "--stage STAGE", "Environment stage name") do |stage|
              options.stage = stage
            end

            opts.on("-k", "--stack STACK", "Stack name") do |stack|
              options.stack = stack
            end

            opts.on("-a", "--app APP", "App name") do |app|
              options.app = app
            end

            opts.on("-u", "--username USERNAME",
            "MongoDB admin username") do |admin_user|
                options.admin_user = admin_user
            end
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

        instance_tags = AwsHelper::InstanceData::get_tags

        options.debug_mode = options.debug_mode || false
        options.stage = options.stage || ENV['STAGE'] || instance_tags["Stage"]
        options.stack = options.stack || ENV['STACK'] || instance_tags["Stack"]
        options.app = options.app || ENV['APP'] || instance_tags["App"]
#        options.admin_user ||= 'aws_admin'
        options.replSet_name = [ options.stack, options.app, options.stage ].join('-')
        options.mongodb_port = MongoDB::MONGODB_DEFAULT_PORT
        options.visibility_mask = options.visibility_mask || string_to_visibility_mask("abc")

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

# Method to initiate the replica set (essentially a wrapper for the 'replSetinitate' command).
def initiate_replSet(mongodb_replSet, stage)

    if mongodb_replSet.is_replSet() and not mongodb_replSet.is_this_replSet()
    then
        raise FatalError, 'Member already belongs to a different Replica Set?!'
    end

    if mongodb_replSet.is_this_replSet()
    then
        $logger.debug 'Mongodb Replica set already inititated...'
    else
        async = false
        begin
            mongodb_replSet.replSet_initiate(async)
        rescue Mongo::OperationFailure => rinit
            $logger.debug 'Failed to initiate Replica Set...'
            $logger.debug rinit.message
            raise
        end
        $logger.debug 'Mongodb Replica set inititated...'
        mongodb_replSet.this_host_added = true
   end
end

## main

exit if __FILE__ != $0

options = parse_options(ARGV)

# Set up global logger
$logger = setup_logger(options.debug_mode)
$logger.info('MongoDB Add Replica Set Member.....')

# use credentials file at .aws/credentials (testing)
# Aws.config[:credentials] = Aws::SharedCredentials.new
# use instance profile (when on instance)
$logger.info('Getting Instance Profile credentials.....')
Aws.config[:credentials] = Aws::InstanceProfileCredentials.new
Aws.config[:region] = AwsHelper::Metadata::region

# Passing admin password via env. is mandatory.
admin_password = ENV.fetch('MONGODB_ADMIN_PASSWORD', nil)
if not admin_password
then
    $logger.err('FAILED: $MONGODB_ADMIN_PASSWORD must be set!!')
    raise 'FAILED: $MONGODB_ADMIN_PASSWORD must be set!!'
end

availability_zone = AwsHelper::Metadata::availability_zone[-1..-1]

# Set up MongoDB replica set object
mongodb_replSet = MongoDB::ReplicaSet.new(
    options.admin_user,
    admin_password,
    options.mongodb_port,
    options.replSet_name
)
this_host_key = mongodb_replSet.this_host_key

locksmith = Locksmith::Dynamodb.new(
  lock_table_name = "mongo-initialisation",
  max_attempts = 240,
  lock_retry_time = 10,
  ttl = 3600
)

lock_attempts = 0

locksmith.lock(options.replSet_name) do
    # lock taken using the replica set name
    rs_add_attempts = 0
    begin

        # Get the mongodb host seed list from S3
        mongodb_host_seed_list = MongoDBSeedList.new(
            s3, options.stage, options.replSet_name, this_host_key
        )

        # Use the seed list to attempt to find the replica set on the network
        mongodb_replSet.find_replSet_service(mongodb_host_seed_list.to_a)

        if mongodb_host_seed_list.any?
        then
            ## If this member hasn't been added (in case when replica set had already
            #  been inititated) then add it now
            mongodb_replSet.add_this_host(options.visibility_mask[availability_zone]) \
                unless mongodb_replSet.this_host_is_replSet_member()
        else
            ## Assume from this point on that we may need to initiate the replica set
            ## but only if the seed list is empty which implies the replica set has not
            ## been deployed before.
            $logger.debug('WARNING: Host Seed List is empty....initiating Replica Set!')
            initiate_replSet(mongodb_replSet)
            $logger.debug('Replica Set inititated')

            # Add Admin User account if not already added.
            if not mongodb_replSet.auth_active
            then
                $logger.debug('Adding admin user....')
                begin
                    mongodb_replSet.add_admin_user()
                    $logger.debug('Admin user added.')
                rescue => e
                    $logger.debug('Failed to add admin user.')
                    $logger.debug(e.message)
                    raise
                end
            end
        end

        # By now it should be possible to connect directly to the replica set
        # This serves as an assertion that the member has been added successfully
        mongodb_replSet.find_replSet_service([this_host_key])
        raise FatalError, 'Could not connect to newly configured Replica Set' \
            unless mongodb_replSet.replSet_found

        # Add the member to the seed list.
        mongodb_host_seed_list.add(this_host_key)

        # Delete any members in the seed list which are no longer in the replica set config
        mongodb_host_seed_list.keep_if { |m| mongodb_replSet.is_replSet_member(m) }

        # Check we still have the lock - if not something's gone badly wrong.
        raise FatalError, 'MongoDB Replica Set Initiation/Config. sync. Lock Error' \
            unless replSetConfLock.this_host_has_lock()

    # Attempt to reconfigure the replica set again for a few times unless a fatal error occurs
    rescue FatalError => fe
        $logger.debug("FATAL Error. Cannot continue:")
        $logger.debug("#{fe.message}")
        raise
    rescue => ce
        if (rs_add_attempts += 1) < MONGODB_REPLSET_RECONFIG_MAX_ATTEMPTS
        then
            $logger.debug('Failed to add MongoDB Replica Set Member.....'+
                "(attempt = #{rs_add_attempts})")
            $logger.debug("#{ce.message}")
            $logger.debug("Sleeping for #{MONGODB_REPLSET_CONNECT_WAIT} seconds.....")
            sleep(MONGODB_REPLSET_CONNECT_WAIT)
            retry
        end
        $logger.info("FAILED: #{ce.message}")
        $logger.info("EXITING...")
        raise
    ensure
       mongodb_replSet.logout()
    end
end

$logger.info('MongoDB Add Replica Set Member COMPLETE!')

exit
