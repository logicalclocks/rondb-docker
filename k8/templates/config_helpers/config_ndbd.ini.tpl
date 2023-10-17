{{ define "config_ndbd" }}
[NDBD]
{{ $offset := ( mul .nodeGroup 3) }}
NodeId={{ add $offset (add .replica 1) }}
NodeGroup={{ .nodeGroup }}
NodeActive={{ .isActive }}
HostName=ndbmtd-{{ .replica }}.node-group-{{ .nodeGroup }}.default.svc.cluster.local
LocationDomainId=0
ServerPort=11860
DataDir=/srv/hops/mysql-cluster/log
FileSystemPath=/srv/hops/mysql-cluster/ndb_data
FileSystemPathDD=/srv/hops/mysql-cluster/ndb_disk_columns
BackupDataDir=/srv/hops/mysql-cluster/ndb/backups
{{ end }}
