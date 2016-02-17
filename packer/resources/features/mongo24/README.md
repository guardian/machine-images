MongoDB 2.4 Server
==================

This feature is initially designed to be used for the Flexible Content database
which uses a dated version of MongoDB. It is designed to work on pre-systemd based
versions of Ubuntu (i.e. Trusty).

The recommendation is that you run the install script when building an AMI and
then use the configure script at instance launch time.

The install script:
 - installs the relevant package
 - installs ruby gems required by the configuration scripts
 - sets up logging for the configuration scripts

The configuration script:
 - creates the configuration and key file for mongo
 - restarts mongo
 - runs a script to initialise a replica set (or attach to an existing replica
   set)
