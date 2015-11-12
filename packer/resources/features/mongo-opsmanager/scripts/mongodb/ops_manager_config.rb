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
require_relative '../util/logger'

module MongoDB
  class OpsManagerConfig
    include Util::LoggerMixin

    attr_reader :key

    def build_tag_key
      tags = AwsHelper::InstanceData::get_tags
      [tags['Stack'], tags['App'], tags['Stage']].join('-')
    end

    def initialize(table_name=nil, key=nil)
      @key = key || build_tag_key
      @table_name = table_name || "mongo.ops-manager-config.#{@key}"
      ensure_table_exists
    end

    def ops_manager_data
      rs_data = fetch_data
      rs_data['OpsManager']
    end

    def fetch_data
      record = dynamo.get_item(
        :table_name => @table_name,
        :key => { :TagKey => @key },
        :consistent_read => true
      ).data.item

      if !record.nil?
        # return the seed list
        record
      else
        begin
          # this is a new config, so...
          gen_key = SecureRandom.base64(24)
          dynamo.put_item(
            :table_name => @table_name,
            :item => {
              :TagKey => @key,
              :OpsManager => { 'GenKey' => gen_key }
            },
            :expected => { :TagKey => { :comparison_operator => 'NULL'} }
          )
          logger.info 'added default record'
        rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException
          logger.info 'record exists'
        end
        fetch_data
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
              :attribute_name => :TagKey,
              :attribute_type => :S
            }
          ],
          :key_schema => [
            {
              :attribute_name => :TagKey,
              :key_type => :HASH
            }
          ],
          :provisioned_throughput => {
            :read_capacity_units => 1,
            :write_capacity_units => 1,
          }
        )

        # wait for table to be created
        dynamo.wait_until(:table_exists, :table_name => @table_name)
      end
    end

    def dynamo
      @db ||= Aws::DynamoDB::Client.new
    end
  end
end
