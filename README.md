Shared machine images
=====================

This repo contains build scripts for base AMIs that get an Ubuntu AMI to a point
where it is easy to use to deploy an application.

AMI building is done using [Packer](https://packer.io/). The packer config files
are in `packer/` and provisioning scripts are kept in `packer/resources/`.

All AMIs produced by scripts in this repo should have:
 - `LaunchPermission` for all AWS accounts that Prism is aware of
 - a useful set of tags that allows image users to identify the source of the
   image

For example - the initial `base-ubuntu` image has the following tags:
 - **Name**: Unique name of the image
 - **BuildName**: The CI build name (currently in TeamCity)
 - **Build**: The build ID from the CI server
 - **Branch**: The source control branch
 - **VCSRef**: The source control commit reference
 - **SourceAMI**: The AMI that packer started from

If an image was not built in a CI environment then one or more of the above
fields will be set to `DEV`. **Never use an AMI marked DEV as they maybe deleted
at any point without checking if anyone is using it.**.

Building locally
----------------

To build locally you will need:
 - A packer installation (set the `PACKER_HOME` environment variable to the
   location of your packer binaries).
 - Amazon access and secret keys in the `AWS_ACCESS_KEY` and `AWS_SECRET_KEY`
   respectively.

Run the `build.sh` in the root of the repository. When not running in
development mode it will step through the process of image creation.

TODO
----

 - Investigate using packers chroot builder to accelerate the build process
 - Make it create PV AMIs if that's desirable
