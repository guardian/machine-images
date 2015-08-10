# Classes that encapsulate Mongo replica sets
require 'mongo'
require 'socket'

module MongoDB
  DEFAULT_PORT = 27017

  # MongoDB server exception error messages.
  # WARNING: This script has been tested ONLY against:
  #           MongoDB v2.4; ruby mongo driver v1.12.0; aws-sdk v1.63.0 and ruby v2.0.0p598.
  #       The Ruby driver for this combined stack does not appear to properly return MongoDB server
  #       error codes when an exception is raised by the server. The script therefore relies
  #       on parsing the error messages returned which may of course change in future versions
  #       of either MongoDB or the other software used by this script.

  REPLSET_NOT_FOUND_ERR_MESS_REGEX = '^Cannot connect to a replica set using seeds'
  REPLSET_INIT_FAILED_ERR_MESS_REGEX = \
          "^Database command 'replSetInitiate' failed: already initialized"
  REPLSET_INIT_OPLOG_ERR_MESS_REGEX = \
          "^Database command 'replSetInitiate' failed: local.oplog.rs is not empty"
  REPLSET_WAIT_STATE_ERR_MESS = "Transitioning Member Wait state"
  REPLSET_INIT_WAIT_ERR_MESS = "Database command 'replSetGetStatus' failed:"+
                                           " Received replSetInitiate - should come online shortly."
  REPLSET_ALREADY_INIT_ERR_MESS_REGEX = "Database command '[\\w]+' failed:"+
                                           " local.oplog.rs is not empty on the initiating member."+
                                           "  cannot initiate."
  REPLSET_INVALID_STATE_ERR_MESS = 'Replica Set Member has INVALID state!'

  # Number of attempts, and wait in seconds for each attempt, for MongoDB replica set member to
  # complete an initiation (i.e. following a 'replSetInitiate' command).
  REPLSET_INIT_WAIT = 3
  REPLSET_INIT_ATTEMPTS = 60

  # Number of attempts, and wait in seconds for each attempt, for MongoDB replica set member to
  # complete a reconfiguration (i.e. following a 'replSetReconfig' command).
  REPLSET_RECONFIG_WAIT = 3
  REPLSET_RECONFIG_ATTEMPTS = 60

  # MongoDB replic set member states that are considered to be a 'non-failed' state
  NON_FAILED_STATES = [0,1,2,3,5,6,7,9]

  # MongoDB member states
  STATES = {
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
  STATES.default = 'NONE'

  # Number of attempts, and wait in seconds for each attempt, to connect to the replica set using
  # a host seed list
  REPLSET_CONNECT_WAIT = 10
  REPLSET_CONNECT_ATTEMPTS = 60

  # Maximum attempts to add this host to the replica set before giving up.
  REPLSET_RECONFIG_MAX_ATTEMPTS = 1
  # TODO REPLSET_RECONFIG_MAX_ATTEMPTS = 240


  # Class to encapsulate complexities and detail of accessing a MongoDB Replica Set
  class ReplicaSet

    attr_accessor :this_host_added
    attr_reader :this_host_key, :replSet_name,
                :replSet_primary_found, :init_config, :config

    def initialize(config)
      @config = config
      this_host_ip = IPSocket.getaddress(Socket.gethostname)
      @this_host_key = "#{this_host_ip}:#{DEFAULT_PORT}"
      @client
      @connected_host
      @connected_port
      @connected_host_key
      @primary
      @secondaries
      @replSet_primary_found = false
      @this_host_added = false

      rs_security = config.security_data
      @admin_user = rs_security[:admin_user]
      @admin_password = rs_security[:admin_password]
      @init_config = {
        "_id" => @replSet_name,
        'members' => [{ '_id' => 0, 'host' => @this_host_key }]
      }
    end

    # Direct local connect on the current host
    def local_connect_auth
      return Mongo::Client.new(
        [ "127.0.0.1:#{DEFAULT_PORT}"],
        :database => 'admin',
        :user => @admin_user,
        :password => @admin_password,
        :connect_timeout => REPLSET_CONNECT_WAIT,
        # override connection mode (otherwise it detects a replicaset)
        :connect => :direct
      )
    end

    def local_connect_bypass
      return Mongo::Client.new(
        [ "127.0.0.1:#{DEFAULT_PORT}"],
        :database => 'admin',
        :connect_timeout => REPLSET_CONNECT_WAIT,
        # override connection mode (otherwise it detects a replicaset)
        :connect => :direct
      )
    end

    def local_connect
      client = local_connect_auth
      if has_admin?(client)
        $logger.debug("Connected locally with auth")
        return client
      else
        $logger.debug("Connected locally using auth bypass")
        return local_connect_bypass
      end
    end

    def has_admin?(client)
      begin
        client.database.collections
        return true
      rescue Mongo::Auth::Unauthorized => noauth
        return false
      end
    end

    # Connect to the replica set via a host seed list
    def replica_set_connect(mongodb_hosts, read_pref = :primary_preferred)
      return Mongo::Client.new(
        mongodb_hosts,
        :user => @admin_user,
        :password => @admin_password,
        :connect_timeout => REPLSET_CONNECT_WAIT,
        :read => {:mode => read_pref},
        :replica_set => @config.name,
        :connect => :replica_set
      )
    end

      # Method to wait for the replica set member to transition to a specific set of states.
      def wait_member_state (
          expected_member_states = ['PRIMARY'],
          max_wait_attempts = REPLSET_INIT_ATTEMPTS,
          wait_time = REPLSET_INIT_WAIT
      )
        wait_attempts = 0
        while wait_attempts < max_wait_attempts
          begin
            replSetMembers = self.get_status()['members']
            replSetThisMember = replSetMembers.find { |m| m['name'] == @this_host_key }
            replSetMemberState = replSetThisMember['state']
          rescue
            replSetMemberState = STATES.invert['UNKNOWN']
          end
          $logger.debug("ReplSet Initiation Member State: #{STATES[replSetMemberState]}")

          return if expected_member_states.include? STATES[replSetMemberState]

          if ! NON_FAILED_STATES.include? replSetMemberState
            # an invalid state - raise an exception
            "#{REPLSET_INVALID_STATE_ERR_MESS} (State=>#{STATES[replSetMemberState]})"
            $logger.debug("ReplSet Member Wait State Error: #{rse.message}")
            raise Mongo::OperationFailure,
                "#{REPLSET_INVALID_STATE_ERR_MESS}" +
                    " (State=>#{STATES[replSetMemberState]})"
          end
          wait_attempts++
          sleep(wait_time)
        end
      end

      # Initiate the Replica Set - this is an asynchronous process so if the
      # async parameter is false this method will wait until the initiation is complete
      def initiate(async=true)
        @client.database.command(:replSetInitiate => @init_config)

        if not async
        then
          expected_member_states = ['PRIMARY']
          max_wait_attempts = REPLSET_INIT_ATTEMPTS
          wait_time = REPLSET_INIT_WAIT
          begin
            # Given the replica set is being initiated on this server
            # then it should become the primary - so wait for it to
            # transition to the primary state
            wait_member_state(
               expected_member_states,
               max_wait_attempts,
               wait_time
            )
          rescue Mongo::Error::OperationFailure => rse
            $logger.debug("ReplSet Init Error: #{rse.message}")
            if rse.message =~ /#{REPLSET_INIT_FAILED_ERR_MESS_REGEX}/
              $logger.debug("Replica set previously initiated")
            else
              raise
            end
          end
        end
      end

      # TODO: Do we need this?
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
                  retry unless (reconfig_attempts += 1) >=  REPLSET_RECONFIG_ATTEMPTS
                  raise
              end
          end
      end

      def create_user(client, username, password, roles=['read'], db='admin')
        db_client = client.use(db)
        result = db_client.database.users.create(
          username,
          password: password,
          roles: roles
        )
      end

      def create_admin_user
          admin_roles=[
              'readWriteAnyDatabase',
              'userAdminAnyDatabase',
              'dbAdminAnyDatabase',
              'clusterAdmin'
          ]
          self.create_user(@client, @admin_user, @admin_password, admin_roles)
      end

      def logout
        @db.command(:logout => 1) if @db
      end

      # Method to get a failed member candidates to remove from the replica set
      def get_members_to_remove
          begin
          # NOTE: if the replica set could not be found then this *could be* because either
          # all members are faulty *or* there is a network partition. Since it is not easy to
          # determine which is the case, it is only safe to remove members
          # if the replica set has been found
              if !replica_set?
                  raise Mongo::OperationFailure,
                      'MongoDB Replica Set could not be found.' +
                          ' No members will be removed from config.'
              end
              failed_members = self.get_status['members'].select \
                   { |m| not (NON_FAILED_STATES.include? m['state'] and m['health'] == 1) }
              failed_members.map { |m| m['name'] }
          rescue NoMethodError, Mongo::OperationFailure
              []
          end
      end

      # Method to add and possibly remove existing member 'non-healthy' members.
      def add_or_replace_member(host_key, visibility=true)

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
          max_wait_attempts = REPLSET_RECONFIG_ATTEMPTS
          wait_time = REPLSET_RECONFIG_WAIT
          wait_member_state(
                 expected_member_states,
                 max_wait_attempts,
                 wait_time
          )

      end

      def add_this_host(visibility=true)
          $logger.debug("Attempting to add #@this_host_ip to Replica Set...")
          self.add_or_replace_member(@this_host_key, visibility)
      end

    def get_config
      local_client = @client.use("local")
      local_client["system.replset"].find().limit(1).first
    end

    def get_status
      @client.database.command(:replSetGetStatus => 1).documents.first
    end

    def name
      begin
        get_config()["_id"]
      rescue
        nil
      end
    end

    def replica_set?
      !name.nil?
    end

    def replica_set_connection?
      @client.cluster.topology.replica_set?
    end

    def member_names
      get_status['members'].map{|m| m['name']}
    end

    def member?(host_key)
      member_names.include?(host_key)
    end

    def authed?
      @client.cluster.servers.first.pool.with_connection do |conn|
        conn.authenticated?
      end
    end

    # Method to connect to the configured replica
    # Either a connection is made to the primary or a local connection is made
    # (if only secondaries or local connections are available).
    def connect
      seed_list = config.seeds
      if !seed_list.empty?
      then
        (1..REPLSET_CONNECT_ATTEMPTS).each do | find_attempts |
          # Attempt to connect to the Replica Set using the seed list
          # Assumption: if this succeeds then the replica set has already been initiated
          # previously and the service can be located on the network
          # (usually because the autoscaled member is simply adding itself back into the set)
          $logger.debug("Connecting to MongoDB replica set (#{seed_list}).....")
          begin
            @client = replica_set_connect(seed_list, :primary_preferred)
            $logger.debug('Connected to MongoDB replica set.....')
            return @client
          rescue => rsce
            # Try a few more times before attempting to initiate the replica set
            # to allow for e.g. temporary network partitions.
            $logger.debug('Failed to connect to MongoDB replica set.....')
            $logger.debug("#{rsce.message}")
            # possible network glitches where the other members can't be reached.
            if find_attempts < REPLSET_CONNECT_ATTEMPTS
            then
              $logger.debug("Sleeping for #{REPLSET_CONNECT_WAIT} seconds.....")
              sleep(REPLSET_CONNECT_WAIT)
              $logger.debug( "Trying again.")
              $logger.debug( "Failed attempts #{find_attempts} "+
                "of #{REPLSET_CONNECT_ATTEMPTS}.....")
            else
              $logger.debug('Replica Set can not be located on the network!!')
            end
          end
        end
      end
      # if can't connect to the replica set then connect locally
      $logger.debug "Can't connect to the Replica Set"
      $logger.debug 'Attempting to Connect to Mongodb locally...'
      @client = local_connect()
      $logger.debug('Connected locally because Replica Set could not be found.....')
      return @client
    end

      private :wait_member_state, :get_members_to_remove

  end
end
