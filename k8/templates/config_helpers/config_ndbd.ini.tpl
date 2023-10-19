{{ define "config_ndbd" }}
{{- $offset := ( mul .nodeGroup 3) -}}
[NDBD]
NodeId={{ add $offset (add .replica 1) }}
NodeGroup={{ .nodeGroup }}
NodeActive={{ .isActive }}
HostName=node-group-{{ .nodeGroup }}-{{ .replica }}.ndbmtd-ng-{{ .nodeGroup }}.default.svc.cluster.local
LocationDomainId=0
ServerPort=11860
DataDir=/srv/hops/mysql-cluster/log
FileSystemPath=/srv/hops/mysql-cluster/ndb_data
FileSystemPathDD=/srv/hops/mysql-cluster/ndb_disk_columns
BackupDataDir=/srv/hops/mysql-cluster/ndb/backups
{{ end }}