# Machine Image Features

This directory holds optional features that are made available on all images.

Features are opt-in - you can selectively enable them at machine boot time according to your needs.

For example - you might want to configure DNS differently. This is not something
that everyone will want (that will be potentially confusing for users of the
image), but it is useful to have in the machine image so it can be trivially
configured when you do want it.

## Enabling a feature

Just add a line to your user-data that executes `/opt/features/<feature name>/install.sh`.

Note: Depending on the feature, the install script might need to be passed some parameters.

## Adding a new feature

Create a new subdirectory for your feature. It will be copied to `/opt/features/` on all images.

In the root of the feature's directory you must provide an `install.sh` file so that people can enable your feature. For example, this script might edit system configuration files or create init scripts.

Optionally, you can also provide a `pre-cache.sh` file, which will be executed by Packer at image build time. This script is a good place to download `apt` packages, tarballs and other 3rd-party dependencies.

### Downloading 3rd-party dependencies

`install.sh` should not download any 3rd-party dependencies such as `apt` packages. This is to ensure that machines can boot quickly and reliably.

If you need to download anything, you should provide a `pre-cache.sh` script and do it in there. This script will be run at image build time, so `install.sh` can assume that it has already run.
