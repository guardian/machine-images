require 'net/http'
require 'json'
require 'aws-sdk'

module AwsHelper
  class Non200Response < RuntimeError; end

  FAILURES = [
      Errno::EHOSTUNREACH,
      Errno::ECONNREFUSED,
      Errno::EHOSTDOWN,
      Errno::ENETUNREACH,
      SocketError,
      Timeout::Error,
      Non200Response,
  ]

  class InstanceData
    def self.get_tags(instance_id = Metadata.instance_id)
      ec2 = Aws::EC2::Client.new
      tag_results = ec2.describe_tags({
        filters: [{name: "resource-id", values: [instance_id]}]
      }).tags
      Hash[ tag_results.map{ |tag| [tag.key, tag.value]} ]
    end
  end

  class Metadata
    @@backoff = lambda { |num_failures| Kernel.sleep(1.2 ** num_failures) }

    def self.open_connection
      http = Net::HTTP.new('169.254.169.254', 80, nil)
      http.open_timeout = 5
      http.read_timeout = 5
      http.start
      yield(http).tap { http.finish }
    end

    def self.http_get(connection, path)
      response = connection.request(Net::HTTP::Get.new(path))
      if response.code.to_i == 200
        response.body
      else
        raise Non200Response
      end
    end

    def self.get_metadata(path)
      failed_attempts = 0
      begin
        open_connection do |conn|
          http_get(conn, path)
        end
      rescue *FAILURES
        if failed_attempts < @retries
          @@backoff.call(failed_attempts)
          failed_attempts += 1
          retry
        else
          '{}'
        end
      end
    end

    def self.instance_identity
      JSON.parse(get_metadata("/latest/dynamic/instance-identity/document"))
    end

    def self.region
      instance_identity['region']
    end

    def self.availability_zone
      instance_identity['availabilityZone']
    end

    def self.instance_id
      get_metadata("/latest/meta-data/instance-id")
  end
end
