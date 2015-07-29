#! /usr/bin/ruby
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
require 'rubygems'
require 'set'
require 'aws-sdk'
require 'mongo'
require 'socket'
require 'syslog'
require 'optparse'
require 'ostruct'
require 'shellwords'

include Mongo

## Set sys logger facility
SYS_LOG_FACILITY = Syslog::LOG_LOCAL1
#
# S3 'optimistic' lock expiry and waits in seconds for lock to be successfully taken or released.
# The take and release waits assume S3 writes are eventually consistent although from testing
# S3 writes appear to be read consistent for the writer.
OPT_LOCK_DEFAULT_EXPIRY = 3600
OPT_LOCK_TAKE_WAIT = 0
OPT_LOCK_RELEASE_WAIT = OPT_LOCK_TAKE_WAIT

# S3 bucket containing the S3 lock file and host:port keys of replica set members.
MONGODB_HOSTS_BUCKET_NAME = 'flexible-db-hosts'

MONGODB_DEFAULT_PORT = 27017

# MongoDB server exception error messages.
# WARNING: This script has been tested ONLY against:
#           MongoDB v2.4; ruby mongo driver v1.12.0; aws-sdk v1.63.0 and ruby v2.0.0p598.
#       The Ruby driver for this combined stack does not appear to properly return MongoDB server
#       error codes when an exception is raised by the server. The sript therefore relies
#       on parsing the error messages returned which may of course change in future versions
#       of either MongoDB or the other software used by this script.

MONGODB_REPLSET_NOT_FOUND_ERR_MESS_REGEX = '^Cannot connect to a replica set using seeds'
MONGODB_REPLSET_INIT_FAILED_ERR_MESS_REGEX = \
        "^Database command 'replSetInitiate' failed: already initialized"
MONGODB_REPLSET_INIT_OPLOG_ERR_MESS_REGEX = \
        "^Database command 'replSetInitiate' failed: local.oplog.rs is not empty"
MONGODB_REPLSET_WAIT_STATE_ERR_MESS = "Transitioning Member Wait state"
MONGODB_REPLSET_INIT_WAIT_ERR_MESS = "Database command 'replSetGetStatus' failed:"+
                                         " Received replSetInitiate - should come online shortly."
MONGODB_REPLSET_ALREADY_INIT_ERR_MESS_REGEX = "Database command '[\\w]+' failed:"+
                                         " local.oplog.rs is not empty on the initiating member."+
                                         "  cannot initiate."
MONGODB_REPLSET_INVALID_STATE_ERR_MESS = 'Replica Set Member has INVALID state!'

# Number of attempts, and wait in seconds for each attempt, for MongoDB replica set member to
# complete an initiation (i.e. following a 'replSetInitiate' command).
MONGODB_REPLSET_INIT_WAIT = 3
MONGODB_REPLSET_INIT_ATTEMPTS = 60

# Number of attempts, and wait in seconds for each attempt, for MongoDB replica set member to
# complete a reconfiguration (i.e. following a 'replSetReconfig' command).
MONGODB_REPLSET_RECONFIG_WAIT = 3
MONGODB_REPLSET_RECONFIG_ATTEMPTS = 60

# MongoDB replic set member states that are considered to be a 'non-failed' state
MONGODB_NON_FAILED_STATES = [0,1,2,3,5,6,7,9]

# MongoDB member states
MONGODB_STATES = {
    0  => 'STARTUP',
    1  => 'PRIMARY',
    2  => 'SECONDARY',
    3  => 'RECOVERING',
    5  => 'STARTUP2',
    6  => 'UNKNOWN',
    7  => 'ARBITER',
    8  => 'DOWN',
    9  => 'ROLLBACK',
    10 => 'REMOVED'
}
MONGODB_STATES.default = 'NONE'

# Number of attempts, and wait in seconds for each attempt, to get the S3 'optimistic' lock
MONGODB_REPLSET_LOCK_WAIT = 30
MONGODB_REPLSET_TAKE_LOCK_MAX_ATTEMPTS = 240

# Number of attempts, and wait in seconds for each attempt, to connect to the replica set using
# a host seed list
MONGODB_REPLSET_CONNECT_WAIT = 10
MONGODB_REPLSET_CONNECT_ATTEMPTS = 60

# Maximum attempts to add this host to the replica set before giving up.
MONGODB_REPLSET_RECONFIG_MAX_ATTEMPTS = 240

# Class to encapsulate AWS S3 access using IAM Role/Instance Profile credentials
class S3 < AWS::S3

    def initialize

        @credentials = AWS::Core::CredentialProviders::EC2Provider.new

        AWS.config(
           :credential_provider => @credentials,
           :region => 'eu-west-1'
        )
        super
    end

end

## Distributed Lock Mechanism
#
# When reconfiguring a Replica set, it's important to serialize this so that only one member is
# attempting to do this at a time - otherwise more than one distinct replica sets *might*
# be created.
# A more sophisticated distributed locking mechanism should probably be used
# but for now, S3 is used.
#
# The following class provides this serialisation using AWS S3 and provides an 'optimistic' lock.
# 'Optimistic' because of the potential for eventual consistency issues where it is assumed
# that the request to take the lock is *not* guaranteed to succeed.
# This class encapsulates the S3 based optimistic lock access.
class S3OptLockError < StandardError
end
class S3OptimisticLock

    attr_reader :this_host_key,
                :s3_obj_name, :s3_obj,
                :s3_bucket_name, :s3_bucket,
                :expiry_in_secs

    def initialize(
       s3, s3_bucket_name, s3_obj_name, this_host_key, expiry_in_secs=OPT_LOCK_DEFAULT_EXPIRY
    )

        @s3 = s3
        @this_host_key = this_host_key
        @s3_bucket_name = s3_bucket_name
        @s3_bucket = @s3.buckets[@s3_bucket_name]
        @s3_obj_name = s3_obj_name
        @s3_obj = @s3_bucket.objects[@s3_obj_name]
        @expiry_in_secs = expiry_in_secs

    end

    def take_lock
        @s3_obj.write(@this_host_key) if self.lock_has_expired or self.this_host_has_lock
        sleep(OPT_LOCK_TAKE_WAIT)
        return true if self.this_host_has_lock
        raise S3OptLockError, 'Failed to Take OptLock!'
    end

    def release_lock
        @s3_obj.write('') if self.this_host_has_lock
        sleep(OPT_LOCK_RELEASE_WAIT)
        return if not self.this_host_has_lock
        raise S3OptLockError, 'Failed to Release OptLock!'
    end

    def read_lock_key
        begin
            @s3_obj.read unless self.lock_has_expired
        rescue AWS::S3::Errors::NoSuchKey
            nil
        end
    end

    def lock_taken_time
        begin
            @s3_obj.last_modified unless self.lock_has_expired
        rescue AWS::S3::Errors::NoSuchKey
            nil
        end
    end

    def lock_has_expired
        begin
            @s3_obj.read.empty? or Time.now() - @s3_obj.last_modified >= @expiry_in_secs
        rescue AWS::S3::Errors::NoSuchKey
            true
        end
    end

    def host_has_lock(host_key)
        self.read_lock_key == host_key
    end

    def this_host_has_lock
        self.host_has_lock(@this_host_key)
    end

    def is_locked
        not self.read_lock_key.nil? and not self.read_lock_key.empty?
    end

end

# Class to encapsulate complexities and detail of accessing a MongoDB Replica Set
class MongoDbReplSet

    attr_accessor :this_host_added
    attr_reader :this_host_key, :auth_active, :replSet_name, :replSet_initiated,
                :replSet_found, :replSet_primary_found, :init_config

    def initialize(
        admin_user=nil,
        admin_password=nil,
        replSet_name = "iddb-TEST",
        mongodb_port = MONGODB_DEFAULT_PORT
    )
        @this_host = Socket.gethostname
        @this_host_ip = IPSocket.getaddress(@this_host)
        @replSet_name = replSet_name
        @mongodb_port = mongodb_port
        @this_host_key = "#@this_host_ip:#@mongodb_port"
        @connection
        @connected_host
        @connected_port
        @connected_host_key
        @db
        @primary
        @secondaries
        @auth_active
        @replSet_found = false
        @replSet_primary_found = false
        @replSet_initiated = false
        @this_host_added = false
        @admin_user = admin_user
        @admin_password = admin_password
        @init_config = {
            "_id" => @replSet_name,
            'members' => [{ '_id' => 0, 'host' => @this_host_key }]
        }

    end

    # Direct local connect on the current host
    def local_connect(auth=true)
        @connection = MongoClient.new
        @db = @connection['admin']
        self.auth(@admin_user, @admin_password) if auth
    end

    # Connect to the replica set via a host seed list
    def replSet_connect(mongodb_hosts=[@this_host_key], read_pref = :primary_preferred, auth=true)
        @connection = MongoReplicaSetClient.new(
                          mongodb_hosts,
                          :connect_timeout => MONGODB_REPLSET_CONNECT_WAIT,
                          :read => read_pref
        )
        @db = @connection['admin']
        @primary = @connection.primary
        @secondaries = @connection.secondaries
        if @connection.primary?
        then
            @connected_host = @primary[0]
            @connected_port = @primary[1]
            @connected_host_key = "#@connected_host:#@connected_port"
            @replSet_primary_found = true
        else
            # NOTE: The driver doesn't appear to honour the read preference if
            # for any reason, the primary is not available.
            # It is uncertain if this is a feature or bug but for
            # reads to succeed (e.g. the rs.config) a direct re-connection
            # to the secondary is required here for secondary reads to succeed.
            @replSet_primary_found = false
            @connected_host_key = self.is_master()['me']
            @connected_host = @connected_host_key.split(':')[0]
            @connected_port = @connected_host_key.split(':')[1]
            begin
                @connection = MongoClient.new(
                          @connected_host,
                          @connected_port,
                          :connect_timeout => MONGODB_REPLSET_CONNECT_WAIT
                )
                @db = @connection['admin']
            rescue
                @connected_host_key = @connected_host = @connected_port = @connection = nil
            end
        end
        $logger.debug(
            "Connnected to host #@connected_host_key" +
            " (*#{@replSet_primary_found ? 'PRIMARY' : 'SECONDARY'}*)."
        )
        $logger.debug("Authenticating Admin (*#@admin_user*)...")
        self.auth(@admin_user, @admin_password) if auth
    end

    # Method to wait for the replica set member to transition to a specific set of states.
    def wait_member_state (
        expected_member_states = ['PRIMARY'],
        max_wait_attempts = MONGODB_REPLSET_INIT_ATTEMPTS,
        wait_time = MONGODB_REPLSET_INIT_WAIT
    )
        wait_attempts = 0
        begin
            begin
                replSetMembers = self.get_status()['members']
                replSetThisMember = replSetMembers.find { |m| m['name'] == @this_host_key }
                replSetMemberState = replSetThisMember['state']
            rescue
                replSetMemberState = MONGODB_STATES.invert['UNKOWN']
            end
            $logger.debug(
               "ReplSet Initiation Member State: #{MONGODB_STATES[replSetMemberState]}")
            if not expected_member_states.include? MONGODB_STATES[replSetMemberState]
            then
                if MONGODB_NON_FAILED_STATES.include? replSetMemberState
                   # assume the member is transitioning to allowed state - wait
                   raise Mongo::OperationFailure, MONGODB_REPLSET_WAIT_STATE_ERR_MESS
                else
                    # an invalid state - raise an exception
                    raise Mongo::OperationFailure,
                        "#{MONGODB_REPLSET_INVALID_STATE_ERR_MESS}" +
                            " (State=>#{MONGODB_STATES[replSetMemberState]})"
                end
            end
        rescue Mongo::OperationFailure => rse
            $logger.debug("ReplSet Member Wait State Error: #{rse.message}")
            if (wait_attempts += 1) < max_wait_attempts
            then
                sleep(wait_time)
                retry
            end
            raise
        end
    end

    # Initiate the Replica Set - this is an asynchronous process so if the
    # async parameter is false this method will wait until the initiation is complete
    def replSet_initiate(async=true)

        init_attempts=0

        @db.command({"replSetInitiate" => @init_config })

        if not async
        then
            expected_member_states = ['PRIMARY']
            max_wait_attempts = MONGODB_REPLSET_INIT_ATTEMPTS
            wait_time = MONGODB_REPLSET_INIT_WAIT
            begin
                # Given the replica set is being initiated on this server
                # then it should become the primary - so wait for it to
                # transition to the primary state
                wait_member_state(
                   expected_member_states,
                   max_wait_attempts,
                   wait_time
                )
            rescue Mongo::OperationFailure => rse
                $logger.debug("ReplSet Init Error: #{rse.message}")
                @replSet_initiated = true if (
                    rse.message =~ /#{MONGODB_REPLSET_INIT_FAILED_ERR_MESS_REGEX}/
                )
                raise
            end
        end
        @replSet_initiated = true
    end

    def replSet_reconfig(config, force=false)
        begin
            @db.command({'replSetReconfig' => config, 'force' => force })
        rescue Mongo::OperationTimeout => e
            raise if not force
            reconfig_attempts = 0
            begin
                self.get_status()
            rescue => se
                $logger.debug("Reconfig Status error:")
                $logger.debug("#{se.message}")
                retry unless (reconfig_attempts += 1) >=  MONGODB_REPLSET_RECONFIG_ATTEMPTS
                raise
            end
        end
    end

    def add_user(username, password, roles=['read'], db='admin')
        @connection[db].add_user(username, password, nil, :roles => roles)
    end

    def add_admin_user()
        admin_roles=[
            'readWriteAnyDatabase',
            'userAdminAnyDatabase',
            'dbAdminAnyDatabase',
            'clusterAdmin'
        ]
        self.add_user(@admin_user, @admin_password, admin_roles)
    end

    def admin_user_exists()
        @db['system.users'].find({'user'=> @admin_user}).any?
    end

    def logout
      @db.command(:logout => 1) if @db
    end

    # This method authenticates a database user.
    # Determining the state of the authentication confguration on the target version
    # of MongoDB (version 2.4) is not particularly simple and requires deliberate read
    # exception handling. Added to that, the server behaves differently depending on whether
    # the replica set has been initiated. If it hasn't been initiated then it's assumed here
    # that authentication is not 'active'
    def auth(username, password, db_name='admin')
        @connection.remove_auth(db_name)
        db = @connection[db_name]
        begin
            # Try and read the list of collections in the database (default is admin db)
            db.collection_names
            @auth_active = false
        rescue Mongo::OperationFailure, Mongo::ConnectionFailure => coe
            if  coe.message =~ /^not authorized for query/
                # Access has been denied so looks like authentication is active
                @auth_active = true
            elsif coe.message =~ /^not master and slaveOk=false/
                # Looks like the replication set hasn't been configured yet so authentication
                # may or may not be active - assume inactive.
                @auth_active = false
            else
                # Any other exception means there's some sort other issue but assume
                # authentication is active anyhow.
                @auth_active = true
                raise
            end
        end
        # try authenticating the user. Even if authentication is not active this should still
        # work so long as the user exists.
        begin
            db.authenticate(username, password, nil, db_name)
        rescue Mongo::AuthenticationError => ae
            # If authentication failed then either authentication is disabled and the user
            # doesn't exist (in which case we don't care since authentication is disabled)
            # or authentication has genuinely failed in which case we re-raise the exception
            raise unless (
                not @auth_active and
                ae.message == "Failed to authenticate user '#{username}' on db '#{db_name}'."
            )
        end
    end

    # Method to get a failed member candidates to remove from the replica set
    def get_members_to_remove
        begin
        # NOTE: if the replica set could not be found then this *could be* because either
        # all members are faulty *or* there is a network partition. Since it is not easy to
        # determine which is the case, it is only safe to remove members
        # if the replica set has been found
            if not @replSet_found
                raise Mongo::OperationFailure,
                    'MongoDB Replica Set could not be found.' +
                        ' No members will be removed from config.'
            end
            failed_members = self.get_status['members'].select \
                 { |m| not (MONGODB_NON_FAILED_STATES.include? m['state'] and m['health'] == 1) }
            failed_members.map { |m| m['name'] }
        rescue NoMethodError, Mongo::OperationFailure
            []
        end
    end

    # Method to add and possibly remove existing member 'non-healthy' members.
    def add_or_replace_member(hostname, visibility=true, mongodb_port=MONGODB_DEFAULT_PORT)

        host_key = "#{hostname}:#{mongodb_port}"

        # Get the current replica set configuration
        replSetConfig = self.get_config()

        replSetConfig = @init_config if not replSetConfig

        # we need to increment the config version when updating it
        replSetConfig['version'] += 1 if replSetConfig['version']

        # if we're adding a members then this implies that there must be failed members to
        # remove
        members_to_remove = get_members_to_remove()
        if members_to_remove.any?
            $logger.debug("Target members to remove from Replica Set: #{members_to_remove}...")
            replSetConfig['members'].reject! { |m| members_to_remove.include? m['host'] }
        end

        # unless already a member, add the new member
        # (and minus old failed members if necessary) to configuration
        new_config = replSetConfig
        unless new_config['members'].any? {
            |m| m['host'] == host_key or members_to_remove.include? host_key
        }
            # get an id for the new member where the id is not already in use
            new_member_id = new_config['members'].map { |m| m['_id'] }.max + 1
            new_config['members'] = new_config['members'] << {
                '_id'      => new_member_id,
                'host'     => host_key,
                'priority' => visibility ? 1 : 0,
                'hidden'   => (not visibility)
            }
        end

        $logger.debug("Reconfiguring Replica Set:")
        $logger.debug("#{new_config.inspect}")
        begin
            self.replSet_reconfig(new_config, true )
        rescue => ecfg
            $logger.debug("Reconfiguring Replica Set Failed:")
            $logger.debug("#{ecfg.message}")
            raise
        end
        expected_member_states = ['PRIMARY','SECONDARY','STARTUP2']
        max_wait_attempts = MONGODB_REPLSET_RECONFIG_ATTEMPTS
        wait_time = MONGODB_REPLSET_RECONFIG_WAIT
        wait_member_state(
               expected_member_states,
               max_wait_attempts,
               wait_time
        )

    end

    def add_this_host(visibility=true, mongodb_port=MONGODB_DEFAULT_PORT)
        $logger.debug("Attempting to add #@this_host_ip to Replica Set...")
        self.add_or_replace_member(@this_host_ip, visibility, mongodb_port)
    end

    def get_config
        @connection['local']['system.replset'].find_one
    end

    def get_status
        @db.command({"replSetGetStatus" => 1 })
    end

    def is_master
        @db.command({"isMaster" => 1 })
    end

    def this_host_is_master(replSetName)
        begin
           is_masterDetails = self.is_master
           is_masterDetails['ismaster'] and is_masterDetails['setName'] == replSetName
        rescue
            false
        end
    end

    def is_replSet
        begin
            not self.get_config()["_id"].nil?
        rescue
            false
        end
    end

    def is_this_replSet(replSetName=@replSet_name)
        begin
            self.get_config()["_id"] == replSetName
        rescue
            false
        end
    end

    def is_replSet_member(host_key)
        begin
           self.get_status()['members'].select { |m| m['name'] ==  host_key }.any?
        rescue
           false
        end
    end

    def this_host_is_replSet_member()
        self.is_replSet_member @this_host_key
    end

    # Method to 'find' the replica set service on the netork from a given host seed list
    # Either a connection is made to the primary or a local connection is made (if only
    # secondaries or local connections are available).
    def find_replSet_service(mongodb_host_seed_list)

        @replSet_found = false
        if mongodb_host_seed_list.any?
        then
            (1..MONGODB_REPLSET_CONNECT_ATTEMPTS).each do | find_attempts |
                # Attempt to connect to the Replica Set using the seed list
                # Assumption: if this succeeds then the replica set has already been initiated
                # previously and the service can be located on the network
                # (usually because the autoscaled member is simply adding itself back into the set)
                $logger.debug("Connecting to MongoDB replica set (#{mongodb_host_seed_list}).....")
                begin
                    self.replSet_connect(mongodb_host_seed_list, :primary_preferred)
                    $logger.debug('Connected to MongoDB replica set.....')
                    @replSet_found = true
                    break
                rescue => rsce
                    # Try a few more times before attempting to initiate the replica set
                    # to allow for e.g. temporary network partitions.
                    $logger.debug('Failed to connect to MongoDB replica set.....')
                    $logger.debug("#{rsce.message}")
                    # possible network glitches where the other members can't be reached.
                    if find_attempts < MONGODB_REPLSET_CONNECT_ATTEMPTS
                    then
                       $logger.debug("Sleeping for #{MONGODB_REPLSET_CONNECT_WAIT} seconds.....")
                       sleep(MONGODB_REPLSET_CONNECT_WAIT)
                       $logger.debug( "Trying again.")
                       $logger.debug( "Failed attempts #{find_attempts} "+
                           "of #{MONGODB_REPLSET_CONNECT_ATTEMPTS}.....")
                    else
                       $logger.debug('Replica Set can not be located on the network!!')
                    end
                end
            end
        end
        # if can't connect to the replica set then connect locally
        if not @replSet_found
        then
            $logger.debug "Can't connect to the Replica Set"
            $logger.debug 'Attempting to Connect to Mongodb locally...'
            self.local_connect()
            $logger.debug('Connected locally because Replica Set could not be found.....')
        end
    end

    private :wait_member_state, :get_members_to_remove

end

## Service Discovery
#
# We need a means of finding the replica set primary host so that an 'auto-scaled' host
# can add itself into the replica set at EC2 instance launch/bootstrap time.
# This should probably use a more comprehensive service discovery mechanism but for now we simply
# maintain a list of replica set hosts in S3.
#
class MongoDBSeedList < Set

    # Set object clear method does not use the class's delete method so inherited method is
    # set to 'undefined'.
    undef_method :clear

    def initialize(s3, stage, replSet_name, this_host_key)
        @s3 = s3
        @stage = stage
        @replSet_name = replSet_name
        @this_host_key = this_host_key
        @mongodb_hosts_bucket = s3.buckets[MONGODB_HOSTS_BUCKET_NAME]
        @mongodb_hosts_bucket_dir = "#@stage/#@replSet_name"
        #
        # Construct a host seed list from S3 that will be used to try and connect to the
        # replica set initially at least
        #
        super()
        @mongodb_hosts_bucket.objects.each do |host|
            self << host.key.split('/')[-1] \
                if host.key =~ /^#@mongodb_hosts_bucket_dir\/[\w.-]+:\d+$/
        end
    end

    def add(obj)
        @mongodb_hosts_bucket.objects["#@mongodb_hosts_bucket_dir/#{obj}"].write(obj)
        super
    end

    def delete(obj)
        @mongodb_hosts_bucket.objects["#@mongodb_hosts_bucket_dir/#{obj}"].delete()
        super
    end

    # NOTE: The Set object does not use the class's delete method for delete_if and keep_if so
    # both need to be overridden here.
    def delete_if
        block_given? or return enum_for(__method__)
        to_a.each { |o| delete(o) if yield(o) }
        self
    end
    def keep_if
        block_given? or return enum_for(__method__)
        to_a.each { |o| delete(o) unless yield(o) }
        self
    end

end

# Set up 'can not continue' exception class
class FatalError < StandardError
end

# Method to convert an 'avaiablitiy zone visibility mask' from a string to a hash
# This is used to determine if a replica set member should be visible (not hidden)
# in a particular AZ.
# The string must be a distinct combination of a, b or c (the assumed AZs)
# An empty string represents 'not visible in all AZs'
def string_to_visibility_mask(visibility_mask_string = 'abc')

    visibility_mask_array = (
        visibility_mask_string.nil? ? ['a','b','c'] : visibility_mask_string.split('')
    )
    unless (
        visibility_mask_array.uniq.sort & ['a','b','c'] == visibility_mask_array.sort
    )
    then
        raise \
            "AZ visibility mask **(#{visibility_mask_string})** must be combination of a, b or c"
    end
    visibility_mask_hash = {'a'=>false,'b'=>false,'c'=>false}
    visibility_mask_array.each { |c| visibility_mask_hash[c] = true }
    visibility_mask_hash
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

            opts.on("-s", "--stage STAGE",
            "development stage (TEST, DEV, PROD)") do |stage|
                options.stage = stage
            end
            opts.on("-u", "--username USERNAME",
            "MongoDB admin username") do |admin_user|
                options.admin_user = admin_user
            end
            opts.on("-r", "--replset_name REPLSET_NAME",
            "MongoDB Replica Set Name") do |replSet_name|
                options.replSet_name = replSet_name
            end
            opts.on("-p", "--port PORT",
            "MongoDB port") do |mongodb_port|
                options.mongodb_port = mongodb_port
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

        options.debug_mode = options.debug_mode || false
        options.stage = options.stage || ENV['STAGE'] || 'TEST'
        options.admin_user = options.admin_user || 'aws_admin'
        options.replSet_name = options.replSet_name ||
            ENV['MONGODB_REPLSET'] || "iddb-#{options.stage}"
        options.mongodb_port = options.mongodb_port || MONGODB_DEFAULT_PORT
        options.visibility_mask = options.visibility_mask ||
            string_to_visibility_mask(ENV['MONGODB_AZ_VISIBILITY_MASK']) ||
                {'a'=>true,'b'=>true,'c'=>true}

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

    logger = Syslog.open(
                            ident = $0,
                            logopt = logopt,
                            facility = SYS_LOG_FACILITY
    )

    logger.mask = Syslog::LOG_UPTO(logmask)

    return logger

end

# Method to initiate the replica set (essentially a wrapper for the 'replSetinitate' command).
def initiate_replSet(mongodb_replSet, stage='TEST')

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

# Passing admin password via env. is mandatory.
admin_password = ENV.fetch('MONGODB_ADMIN_PASSWORD', nil)
if not admin_password
then
    $logger.err('FAILED: $MONGODB_ADMIN_PASSWORD must be set!!')
    raise 'FAILED: $MONGODB_ADMIN_PASSWORD must be set!!'
end

availability_zone = ENV.fetch('EC2_PLACEMENT_AVAILABILITY_ZONE','')[-1..-1]

# Set up MongoDB replica set object
mongodb_replSet = MongoDbReplSet.new(
    options.admin_user,
    admin_password,
    options.replSet_name,
    options.mongodb_port
)
this_host_key = mongodb_replSet.this_host_key

# Set up an 'optimistic lock' in S3 to serialize rs.inititates amongst Autoscaled members.
s3 = S3.new
mongodb_optimistic_lock_obj_name = "#{options.stage}/#{options.replSet_name}/iddb-replset-init"
replSetConfLock = S3OptimisticLock.new(
    s3,
    MONGODB_HOSTS_BUCKET_NAME,
    mongodb_optimistic_lock_obj_name,
    this_host_key
)

lock_attempts = 0
begin

    # Take the 'optimistic' lock to serialise replica set config changes in autoscale group.
    # This is necessary to avoid a 'split' replica set if more than one member is unavailable
    $logger.debug('Attempting to take S3 lock')
    begin
        raise S3OptLockError, 'Failed to get ReplSet Config lock' \
            unless replSetConfLock.take_lock()
    rescue S3OptLockError
        if (lock_attempts += 1) < MONGODB_REPLSET_TAKE_LOCK_MAX_ATTEMPTS
        then
            sleep(MONGODB_REPLSET_LOCK_WAIT)
            $logger.debug('Attempting to take S3 lock again...')
            retry
        end
        $logger.debug("S3 Locking Issue:")
        $logger.debug("#{le.message}")
        raise
    end
    $logger.debug('S3 lock successfully taken')

    # Optimistic lock taken - initiate the Replica set on this host
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
ensure
    $logger.debug('Releasing S3 lock')
    replSetConfLock.release_lock()
end

$logger.info('MongoDB Add Replica Set Member COMPLETE!')

exit
