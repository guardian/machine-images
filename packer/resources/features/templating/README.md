This contains some supporting files that are probably useful for other scripts.

### subst.sh: a script to undertake substitutions in configuration files

The simple idea with subst.sh is to replace instances of `@KEY@` with `value` in
a provided file or list of files. The set of keys can be specified or
retrieved from the instance tags and cloudformation parameters.

See the help text in the script for more details.

### metadata.sh: support functions for retrieving metadata

This provides a selection of bash functions that return metadata as simple
values or bash associative arrays containing instance tag and cloudformation
parameter keys and values.

The best way to use this is to source the file in your own bash script and call
the appropriate functions. Look at subst.sh and also the native-packager
installer for examples.
