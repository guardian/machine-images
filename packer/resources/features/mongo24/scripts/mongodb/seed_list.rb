## Service Discovery
#
# We need a means of finding the replica set primary host so that an 'auto-scaled' host
# can add itself into the replica set at EC2 instance launch/bootstrap time.
# This should probably use a more comprehensive service discovery mechanism but for now we simply
# maintain a list of replica set hosts in S3.
#
require 'aws-sdk'

module MongoDB
  class SeedList

    def initialize(table_name, replSet_name)
      @seedlist_table_name = table_name
      @replSet_name = replSet_name
      ensure_table_exists
    end

    def seeds
      fetch_seed_list(@replSet_name)
    end

    def add(obj)
      current = seeds
      if current.include?(obj)
        current
      else
        update_seed_list(@replSet_name, current, current + [obj])
        seeds
      end
    end

    def remove(obj)
      current = seeds
      if current.include?(obj)
        update_seed_list(@replSet_name, current, current - [obj])
        seeds
      else
        current
      end
    end

    def update_seed_list(name, old_list, new_list)
      dynamo.update_item(
        :table_name => @seedlist_table_name,
        :key => { :SeedListName => name },
        :update_expression => "SET SeedList = :new_list",
        :condition_expression => "SeedList = :old_list",
        :expression_attribute_values => { ":old_list" => old_list, ":new_list" => new_list }
      )
    end

    def fetch_seed_list(name)
      seed_record = dynamo.get_item(
        :table_name => @seedlist_table_name,
        :key => { :SeedListName => name },
        :consistent_read => true,
      ).data.item

      if !seed_record.nil?
        # return the seed list
        seed_record["SeedList"]
      else
        begin
          dynamo.put_item(
            :table_name => @seedlist_table_name,
            :item => { SeedListName: name, SeedList: [] },
            :expected => { "SeedListName" => { comparison_operator: "NULL" } }
          )
          puts "added default record"
        rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException
          puts "record exists"
        end
        fetch_seed_list(name)
      end
    end


    def ensure_table_exists
      ## Create the table if it doesn't exist
      begin
        dynamo.describe_table(:table_name => @seedlist_table_name)
      rescue Aws::DynamoDB::Errors::ResourceNotFoundException
        dynamo.create_table(
          :table_name => @seedlist_table_name,
          :attribute_definitions => [
            {
              :attribute_name => :SeedListName,
              :attribute_type => :S
            }
          ],
          :key_schema => [
            {
              :attribute_name => :SeedListName,
              :key_type => :HASH
            }
          ],
          :provisioned_throughput => {
            :read_capacity_units => 10,
            :write_capacity_units => 10,
          }
        )

        # wait for table to be created
        dynamo.wait_until(:table_exists, table_name: @seedlist_table_name)
      end
    end

    def dynamo
      @db ||= Aws::DynamoDB::Client.new
    end

  end
end
