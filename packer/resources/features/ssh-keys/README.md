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

Next, you should add a line to the UserData of your cloudformation template to call initialise-keys-and-cron-job.sh with
the bucket name and your team name as parameters. For example:

    { "Fn::Join": [ "", ["/opt/features/ssh-keys/initialise-keys-and-cron-job.sh -b github-team-keys -t ", {"Ref":"GithubTeamName"}, "\n"] ] }
