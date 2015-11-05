require 'httparty'
require_relative '../util/logger'
require 'json'

module MongoDB
  class OpsManagerAPI
    include Util::LoggerMixin
    include HTTParty

    def initialize(ops_manager_config)
      ops_manager_config = ops_manager_config
      self.class.base_uri "#{ops_manager_config['BaseUrl']}/api/public/v1.0/groups/#{ops_manager_config['GroupId']}"
      self.class.digest_auth ops_manager_config['AutomationApiUser'], ops_manager_config['AutomationApiKey']
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
      loop do
        hosts_to_check = automation_agents['results'].map{ |e| e['hostname'] }
        status = automation_status
        goal = status['goalVersion']
        last_goals = status['processes'].select{ |e| hosts_to_check.include?(e['hostname']) }.map{|e| e['lastGoalVersionAchieved']}
        logger.info "Goal: #{goal} Last achieved: #{last_goals}"
        break if last_goals.all? { |e| goal == e }
        sleep 5
      end
      logger.info 'Successfully reached goal state'
    end

    def get_group_cluster_0_id
      clusters = self.class.get("/clusters")

      clusters['results'][0]['id']
    end

    def snapshots
      self.class.get("/clusters/#{get_group_cluster_0_id}/snapshots")
    end

    def create_restore_job_for_snapshot(snapshot)
      post_data = {
          :body => { "snapshotId" => snapshot }.to_json,
          :headers => { 'Content-Type' => 'application/json'}
      }
      restore_job_response = self.class.post("/clusters/#{get_group_cluster_0_id}/restoreJobs", post_data)
      logger.info("Restore job response: #{JSON.parse(restore_job_response.body)}")
      JSON.parse(restore_job_response.body)['results'][0]['id']
    end

    def poll_for_restore_download_uri(restore_job_id, attempt_no=0)
      restore_job_status = self.class.get("/clusters/#{get_group_cluster_0_id}/restoreJobs/#{restore_job_id}")
      if restore_job_status['statusName'] == 'FINISHED' && restore_job_status['delivery']['statusName'] =='READY'
        restore_job_status['delivery']['url']
      else
        if attempt_no < 60
          sleep(5)
          poll_for_restore_download_uri(restore_job_id, attempt_no+1)
        else
          raise FatalError, "Restore job took longer than 10 minutes to create download URL, restore job id #{restore_job_id}"
        end
      end
    end
  end

  class OpsManager
    def initialize(api)
      @api = api
    end

    def save_json(data, filename)
      File.write(filename, JSON.pretty_generate(data))
    end

    def find_replica_set(config, name)
      rs = config['replicaSets'].find{|rs| rs['_id'] == name}
      if rs.nil?
        raise FatalError, "Cannot find replica set #{name} in existing configuration"
      end
      rs
    end

    def set_version(replica_set_name, target)
      # Change the version of mongo
      config = @api.automation_config

      # Get the process names for the named replica set
      rs = find_replica_set(config, replica_set_name)
      rs_process_names = rs['members'].map{|m| m['host']}

      # Update the version
      processes = config['processes']
      processes.each { |p|
        if rs_process_names.include?(p['name'])
          logger.info "Updating process #{p['hostname']} to version #{target}"
          p['version'] = target
        end
      }
      @api.put_automation_config(config)
      @api.wait_for_goal_state
    end

    def clean_up_dead_nodes(replica_set_name, known_hosts)
      # get current config from OpsManager
      config = @api.automation_config
      save_json(config, 'cleanup-01.json')

      # find replica set
      rs = find_replica_set(config, replica_set_name)

      # find all associated processes
      rs_process_names = rs['members'].map{|m| m['host']}
      rs_processes = config['processes'].select{|p| rs_process_names.include?(p['name'])}

      # find unknown processes in the replica set (processes that we didn't find corresponding instances of)
      rs_unknown_processes = rs_processes.reject{|p| known_hosts.include?(p['hostname']) }
      rs_unknown_process_names = rs_unknown_processes.map{|p| p['name']}
      logger.info "Unknown process names in replica set #{replica_set_name}: #{rs_unknown_process_names}"

      unless rs_unknown_processes.empty?
        # remove related process
        config['processes'].reject!{|p| rs_unknown_processes.include?(p)}

        # remove related replicaSet members
        rs['members'].reject! { |m|
          rs_unknown_process_names.include?(m['host'])
        }
        save_json(config, 'cleanup-02.json')

        # push new config to OpsManager
        @api.put_automation_config(config)
        @api.wait_for_goal_state
      end

      # find unknown hosts (from the processes we've just removed)
      unknown_process_hosts = rs_unknown_processes.map{|p| p['hostname']}
      unknown_hosts = @api.hosts['results'].select{|h| unknown_process_hosts.include?(h['hostname'])}

      if unknown_hosts.length > 0
        logger.info "#{unknown_hosts.length}"
        logger.info "DELETE hosts: #{unknown_hosts.map{|h| h['hostname']}}"
        unknown_hosts.each{ |uh|
          @api.delete_hosts(uh['id'])
        }
      end
    end

    def add_self(replica_set_name)
      # check we have an associated registered OpsManager agent
      agents = @api.automation_agents
      this_host = agents['results'].find { |e| e['hostname'].include?(Socket.gethostname) }
      if this_host.nil?
        raise FatalError, 'This host does not have a registered automation agent'
      end

      config = @api.automation_config
      save_json(config, 'initial.json')
      processes = config['processes']
      this_process = processes.find { |e| e['hostname'] == this_host['hostname'] }

      rs = find_replica_set(config, replica_set_name)

      if this_process.nil?
        new_node = processes[0].clone
        new_node['hostname'] = this_host['hostname']
        new_node['alias'] = IPSocket.getaddress(Socket.gethostname)
        new_node['name'] = Socket.gethostname
        processes << new_node

        replica_set_members = rs['members']
        new_member = replica_set_members[0].clone
        new_member['host'] = new_node['name']
        new_member['_id'] = replica_set_members.map{|e| e['_id']}.max + 1
        replica_set_members << new_member

        # check that we are set up for monitoring
        monitoring_versions = config['monitoringVersions']
        this_monitor_version = monitoring_versions.find { |e| e['hostname'] == this_host['hostname']}

        if this_monitor_version.nil?
          new_mv = { 'hostname' => this_host['hostname'] }
          monitoring_versions << new_mv
        end

        logger.info "Adding #{this_host['hostname']} to config"
        save_json(config, 'modified.json')
        @api.put_automation_config(config)
        @api.wait_for_goal_state
      else
        logger.info 'This host is already in the processes list, no work to do'
      end

    end

    def self_install_backup
      # check we have an associated registered OpsManager agent
      agents = @api.automation_agents
      this_host = agents['results'].find { |e| e['hostname'].include?(Socket.gethostname) }
      if this_host.nil?
        raise FatalError, 'This host does not have a registered automation agent'
      end

      config = @api.automation_config
      save_json(config, 'initial.json')

      backup_versions = config['backupVersions']
      this_backup_version = backup_versions.find { |e| e['hostname'] == this_host['hostname']}

      if this_backup_version.nil?
        new_bv = { 'hostname' => this_host['hostname'] }
        backup_versions << new_bv
        logger.info "Adding backup agent to #{this_host['hostname']}"
        save_json(config, 'modified.json')
        @api.put_automation_config(config)
        @api.wait_for_goal_state
      else
        logger.info 'This host already has the backup agent, no work to do'
      end

    end

    def get_latest_snapshot_id
      snapshots = @api.snapshots
      latest_snapshot_id = snapshots['results'][0]['id']
      latest_snapshot_created = snapshots['results'][0]['created']['date']
      logger.info "Latest snapshot has id #{latest_snapshot_id}, create date #{latest_snapshot_created}"
      latest_snapshot_id
    end

    def get_snapshot_download_link(snapshot_id)
      # create restore job for the snapshot
      restore_job_id = @api.create_restore_job_for_snapshot(snapshot_id)
      logger.info "Restore job id: #{restore_job_id}"

      # wait for download link to be ready
      download_link = @api.poll_for_restore_download_uri(restore_job_id)
      logger.info "Snapshot download link: #{download_link}"
      download_link
    end
  end
end