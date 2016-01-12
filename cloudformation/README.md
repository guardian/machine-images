# Cloudformation Templates

| Template   |      Name      |  Description |
| ------------- | ------------- |------------------|
| `elk-stack.template` | ELK (Elastic Search, Logstash and Kibana) | ELK stack running behind Google Authenticator. Used for log aggregation and analysis. |
| `mongo-opsmanager-server.template` | MongoDB OpsManager Main Server Node  | Main MongoDB OpsManager (sometimes referred to as MMS) |
| `mongo-opsmanager-backup.template` | MongoDB OpsManager Backup Node | Node that performs database backups as part of a MongoDB OpsManager orchestration  |
| `mongo-opsmanager.template` | MongoDB Replica Set Node (managed by OpsManager) | Regular database node. Will auto-discover the OpsManager instances at launch and setup will commence. |
| `mongo24.template` | MongoDB Replica Set Node (unmanaged)  | Regular database node. Will auto-discover using a DynamoDB table and add itself to an existing replica set automatically. |
