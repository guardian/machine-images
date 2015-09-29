MongoDB OpsManager Automation
=============================

The recommendation is that you run the appropriate install script when building
an AMI and then use the configure script at instance launch time.

OpsManager Agent
----------------

This feature installs and configures Mongo OpsManager automation agents on a node. It
also provides scripts that will reconfigure an OpsManager group to add new/replacement
nodes into replica sets.

The agent-install script:
 - installs ruby gems required by the configuration scripts
 - sets up logging for the configuration scripts

The agent-configuration script:
 - downloads the automation agent from the OpsManager server
 - creates the configuration for the agent
 - starts the agent
 - runs a script to add self to the automation configuration

OpsManager server
-----------------

This feature pre-installs the required software and settings to run OpsManager
MMS HTTP Service, Backup HTTP Service and Backup Daemon.

The server-install script:
 - installs the mongo repo
 - installs the latest mongo server
 - downloads and installs the MMS server packages
 
