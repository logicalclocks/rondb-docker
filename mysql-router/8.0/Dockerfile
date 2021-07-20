# Copyright (c) 2018, 2021, Oracle and/or its affiliates.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
FROM oraclelinux:8-slim

ARG MYSQL_CLIENT_PACKAGE=mysql-community-client-8.0.26
ARG MYSQL_ROUTER_PACKAGE=mysql-router-community-8.0.26

RUN rpm -U https://repo.mysql.com/mysql80-community-release-el8.rpm \
  && microdnf install -y --disablerepo=ol8_appstream \
     $MYSQL_CLIENT_PACKAGE $MYSQL_ROUTER_PACKAGE \
  && microdnf clean all

COPY run.sh /run.sh
HEALTHCHECK \
	CMD mysqladmin --port 6446 --protocol TCP ping 2>&1 | grep Access || exit 1
EXPOSE 6446 6447 6448 6449 8443
ENTRYPOINT ["/run.sh"]
CMD ["mysqlrouter"]
