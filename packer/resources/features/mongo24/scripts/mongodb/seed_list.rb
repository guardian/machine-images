## Service Discovery
#
# We need a means of finding the replica set primary host so that an 'auto-scaled' host
# can add itself into the replica set at EC2 instance launch/bootstrap time.
# This should probably use a more comprehensive service discovery mechanism but for now we simply
# maintain a list of replica set hosts in S3.
#
module MongoDB
  class SeedList

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
end
