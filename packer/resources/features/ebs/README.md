EBS encrypted volumes
=====================

At the time of writing this, cloudformation did not make it easy to attach
encrypted EBS volumes to instances inside an auto scaling group.

This simple script gets around this by creating and mounting an encrypted
volume during instance boot time.

For more details please look at the help at the top of `add-encrypted.sh`.
