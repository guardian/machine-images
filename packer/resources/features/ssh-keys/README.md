ssh-keys feature
================

Installs keys from an s3 bucket and optionally sets up a cron job to keep the keys up to date.

You can use this feature you must provide either an s3 url to a bucket the instance will have access to containing a file
called authorized_keys. Alternatively, you can use it with the shared keys bucket.

The shared keys bucket
----------------------
There is a lambda set up in the editorial tools AWS account to fetch the keys for teams from the guardian github account
and post them to S3. You can use this to ensure your instances have an always up-to-date set of keys installed. 

To use this feature you'll first need to follow the steps [here](https://github.com/guardian/github-keys-to-s3-lambda) 
to get the lambda to start fetching keys for your team and to get your AWS account access to the bucket if it doesn't 
have it already.

Next, you'll need to modify your cloudformation template to get access to the bucket and enable the feature. See [here](https://github.com/guardian/composer-snapshotter/pull/52/files) for an example of how to do this.

Note: the required parameters initialise-keys-and-cron-job.sh when you're enabling the feature are -b <bucket name> and -t <team name>. Depending on where in the boot script you are calling this feature, you
may wish to add ` || true` on to the end of the command, to ensure that if this step fails (for instance if S3 is down),
then the rest of the boot script will still be executed.

For example: 

    { "Fn::Join": [ "", ["/opt/features/ssh-keys/initialise-keys-and-cron-job.sh -l -b github-team-keys -t ", {"Ref":"GithubTeamName"}, " || true \n"] ] }

You can also optionally include the `-l` parameter if you would like the script to initially try to install keys cached 
in the machine image when it was created (these could be out of date, but would provide ssh access in case of an S3
failure).
