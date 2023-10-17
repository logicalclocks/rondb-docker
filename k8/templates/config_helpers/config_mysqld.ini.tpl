{{ define "config_mysqld" }}
#MySQL Servers, Memcached servers, and Clusterj clients.
[MYSQLD]
NodeId={{ .nodeId }}
LocationDomainId=0
NodeActive={{ .isActive }}
ArbitrationRank=1
HostName=mysqlds-{{ .replica }}.mysqld.default.svc.cluster.local
{{ end }}
