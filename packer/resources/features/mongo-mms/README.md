MongoDB MMS Automation
======================

This feature installs and configures Mongo MMS automation agents on a node. It
also provides scripts that will reconfigure a MMS group to add new/replacement
nodes into replica sets.

The recommendation is that you run the install script when building an AMI and
then use the configure script at instance launch time.

The install script:
 - installs ruby gems required by the configuration scripts
 - sets up logging for the configuration scripts

The configuration script:
 - downloads the automation agent from the MMS server
 - creates the configuration for the agent
 - starts the agent
 - runs a script to add self to the automation configuration
