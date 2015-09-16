require 'httparty'

class OpsManager
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