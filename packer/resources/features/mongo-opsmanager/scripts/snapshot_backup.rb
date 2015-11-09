#! /usr/bin/env ruby
# This script is designed to be run on a schedule. It gets the latest snapshot from opsmanager then encrypts it and
# saves the snapshot to S3. The S3 bucket should be set up to be cross-region.

require 'aws-sdk'
require 'syslog'
require 'optparse'
require 'ostruct'
require 'httparty'

require_relative 'locksmith/dynamo_db'
require_relative 'mongodb/ops_manager'
require_relative 'aws/helpers'
require_relative 'util/logger'
require_relative 'mongodb/rs_config'

## Set sys logger facility
SYS_LOG_FACILITY = Syslog::LOG_LOCAL1

# Set up 'can not continue' exception class
class FatalError < StandardError
end

def logger
  Util::SingletonLogger.instance.logger
end

def parse_options(args)
  # The options specified on the command line will be collected in *options*.
  # Set default values here.
  options = OpenStruct.new
  begin
    opts = OptionParser.new do |opts|

      opts.banner = "\nUsage: #{$0} [options]"

      opts.separator ''
      opts.separator 'Specific options:'

      opts.on('-q', '--quiet', "Run in quiet mode (don't log to stderr)") do
        options.quiet_mode = true
      end

      opts.on('-b', '--backup-bucket bucket', 'Bucket to backup to (required)') do |bucket|
        options.backup_bucket = bucket
      end

      opts.on('-k', '--keys-bucket bucket', 'Bucket to fetch keys from for backup encryption (required)') do |bucket|
        options.keys_bucket = bucket
      end

      opts.on_tail('-h', '--help', 'Show this message') do
        raise
      end

    end

    opts.parse!(args)

    raise OptionParser::MissingArgument if options.backup_bucket.nil? || options.keys_bucket.nil?

    raise "Non-empty list of arguments **(#{args})**" unless args.empty?

    options.debug_mode ||= false

  rescue => e
    STDERR.puts "\nOptions Error: #{e.message}" unless e.message.empty?
    STDERR.puts opts
    STDERR.puts
    exit
  end

  options
end

def get_tag(tag_name)
  instance_tags ||= AwsHelper::InstanceData::get_custom_tags
  instance_tags[tag_name]
end

def get_identity_instances
  tags = AwsHelper::InstanceData::get_custom_tags
  AwsHelper::EC2::get_instances(tags)
end

def check_if_snapshot_new(snapshot_id)
  `grep #{snapshot_id} /tmp/last_snapshot_downloaded.txt`.length == 0
end

def download_import_team_keys
  keyring_document_key = 'flexbackupkeys.gpg'
  logger.info("Downloading document #{keyring_document_key} from bucket #{@options.keys_bucket}")
  s3 = Aws::S3::Client.new
  s3.get_object({bucket: @options.keys_bucket, key: keyring_document_key}, target: '/tmp/flexbackupkeys.gpg')
  `gpg --homedir /home/mongo-backup/ --import /tmp/flexbackupkeys.gpg`
end

def generate_gpg_command(filename)
  keys = `gpg --homedir /home/mongo-backup/ --list-keys | grep uid`
  key_uid_list = keys.split('\n')
  emails = key_uid_list.map{|uid| uid.split('<')[1].tr('>', '').tr("\n", '')}
  emails_as_args = emails.map{|email| "-r #{email}"}.join(' ')
  encrypt_command =  "gpg --homedir /home/mongo-backup/ -e #{emails_as_args} --trust-model always -o /backup/#{filename}"
  logger.info("GPG command: #{encrypt_command}")
  encrypt_command
end

def download_encrypt_backup(download_link)
  # download the file
  file_name=download_link.split('/')[-1] + '.gpg'
  gpg_command = generate_gpg_command(file_name)
  download_encrypt_command = "curl #{download_link} | #{gpg_command}"
  logger.info("Downloading and encrypting using command #{download_encrypt_command}.")
  `#{download_encrypt_command}`
  file_name
end

def upload_to_s3(file_name)
  backup_location = "/backup/#{file_name}"
  time = Time.now
  year_month_day = "#{time.year}-#{time.month}-#{time.day}"
  year_month_day_time = "#{year_month_day}-#{time.hour}:#{time.min}#{time.zone}"
  key = "#{year_month_day}/#{year_month_day_time}-#{file_name}"

  logger.info("Uploading #{backup_location} to bucket #{@options.backup_bucket} with key #{key}")
  s3 = Aws::S3::Resource.new
  object = s3.bucket(@options.backup_bucket).object(key)
  object.upload_file(backup_location)
  `rm #{backup_location}`
end

## main
exit if __FILE__ != $0

# use instance profile (when on instance)
Aws.config[:credentials] = Aws::InstanceProfileCredentials.new
Aws.config[:region] = AwsHelper::Metadata::region

@options = parse_options(ARGV)

# Set up global logger
Util::SingletonLogger.instance.init_syslog(
    ident = 'add_self_to_replset',
    facility = Syslog::LOG_LOCAL1,
    quiet_mode = @options.quiet_mode
)

logger.info('MongoDB: Backup snapshot...')

tags = AwsHelper::InstanceData::get_tags
rs_key = [tags['Stack'], 'db', tags['Stage']].join('-')

replica_set_config = MongoDB::ReplicaSetConfig.new(nil, rs_key)

locksmith = Locksmith::DynamoDB.new(
    lock_table_name = 'mongo-initialisation',
    max_attempts = 240,
    lock_retry_time = 10,
    ttl = 3600
)

locksmith.lock(replica_set_config.key) do
  ops_manager_config = replica_set_config.ops_manager_data
  @ops_manager = MongoDB::OpsManager.new(MongoDB::OpsManagerAPI.new(ops_manager_config))
end

latest_snapshot_id = @ops_manager.get_latest_snapshot_id
if check_if_snapshot_new(latest_snapshot_id)
  # save the id of the snapshot to disk
  `echo #{latest_snapshot_id} > /tmp/last_snapshot_downloaded.txt`
  # fetch the snapshot download link
  @download_link = @ops_manager.get_snapshot_download_link(latest_snapshot_id)
  # download and import keys from s3
  download_import_team_keys
  # download backup, encrypting at the same time
  encrypted_backup_name=download_encrypt_backup(@download_link)
  # upload backup to s3
  upload_to_s3(encrypted_backup_name)
  logger.info('MongoDB: Snapshot backup complete!')
else
  logger.info ('Snapshot already backed up. Aborting.')
end
