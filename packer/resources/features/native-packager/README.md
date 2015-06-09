Install a package produced by the sbt-native-packager plugin.

This script downloads, installs and optionally starts the package using various
assumptions. The assumptions include the download location of the package (we
guess the path from the tags of the instance and Riff-Raff's upload
conventions), the user to create, how to generate an upstart file and the
installation location.

For further details have a look at the install script.
