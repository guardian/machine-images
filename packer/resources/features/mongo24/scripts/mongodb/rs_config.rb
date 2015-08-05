## Service Discovery
#
# We need a means of finding the replica set primary host so that an 'auto-scaled' host
# can add itself into the replica set at EC2 instance launch/bootstrap time.
# This should probably use a more comprehensive service discovery mechanism but for now we simply
# maintain a list of replica set hosts in S3.
#
require 'aws-sdk'
require 'securerandom'
require_relative '../aws/helpers'

module MongoDB
  class ReplicaSetConfig

    attr_reader :name

    def build_replica_set_name
      tags = AwsHelper::InstanceData::get_tags
      [tags['Stack'], tags['App'], tags['Stage']].join('-')
    end

    def initialize(table_name=nil, name=nil)
      @name = name || build_replica_set_name
      @table_name = table_name || "mongo.rsconfig.#{@name}"
      ensure_table_exists
    end

    def seeds
      fetch_replica_data['SeedList']
    end

    def security_data
      rs_data = fetch_replica_data
      { key: rs_data['Key'],
        admin_user: rs_data['AdminUser'],
        admin_password: rs_data['AdminPassword'] }
    end

    def add_seed(obj)
      current = seeds
      if current.include?(obj)
        current
      else
        update_seed_list(current, current + [obj])
        seeds
      end
    end

    def remove_seed(obj)
      current = seeds
      if current.include?(obj)
        update_seed_list(current, current - [obj])
        seeds
      else
        current
      end
    end

    def update_seed_list(old_list, new_list)
      dynamo.update_item(
        :table_name => @table_name,
        :key => { :ReplicaSetName => @name },
        :update_expression => "SET SeedList = :new_list",
        :condition_expression => "SeedList = :old_list",
        :expression_attribute_values => { ":old_list" => old_list, ":new_list" => new_list }
      )
    end

    def fetch_replica_data
      replica_set_record = dynamo.get_item(
        :table_name => @table_name,
        :key => { :ReplicaSetName => @name },
        :consistent_read => true,
      ).data.item

      if !replica_set_record.nil?
        # return the seed list
        replica_set_record
      else
        begin
          # this is a new replica set config, so
          admin_password = SecureRandom.base64
          key = SecureRandom.base64(700)
          dynamo.put_item(
            :table_name => @table_name,
            :item => {
              ReplicaSetName: @name,
              SeedList: [],
              AdminUser: "aws-admin",
              AdminPassword: admin_password,
              Key: key
            },
            :expected => { "SeedListName" => { comparison_operator: "NULL" } }
          )
          puts "added default record"
        rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException
          puts "record exists"
        end
        fetch_replica_data
      end
    end

    def ensure_table_exists
      ## Create the table if it doesn't exist
      begin
        dynamo.describe_table(:table_name => @table_name)
      rescue Aws::DynamoDB::Errors::ResourceNotFoundException
        dynamo.create_table(
          :table_name => @table_name,
          :attribute_definitions => [
            {
              :attribute_name => :ReplicaSetName,
              :attribute_type => :S
            }
          ],
          :key_schema => [
            {
              :attribute_name => :ReplicaSetName,
              :key_type => :HASH
            }
          ],
          :provisioned_throughput => {
            :read_capacity_units => 1,
            :write_capacity_units => 1,
          }
        )

        # wait for table to be created
        dynamo.wait_until(:table_exists, table_name: @table_name)
      end
    end

    def dynamo
      @db ||= Aws::DynamoDB::Client.new
    end

  end
end
