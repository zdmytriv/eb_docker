#!/bin/bash
#==============================================================================
# Copyright 2012 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Amazon Software License (the "License"). You may not use
# this file except in compliance with the License. A copy of the License is
# located at
#
#       http://aws.amazon.com/asl/
#
# or in the "license" file accompanying this file. This file is distributed on
# an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
# implied. See the License for the specific language governing permissions
# and limitations under the License.
#==============================================================================

set -e

. /opt/elasticbeanstalk/hooks/common.sh

EB_CONFIG_HTTP_PORT=$(/opt/elasticbeanstalk/bin/get-config container -k instance_port)

if is_rhel; then
	cat > /etc/nginx/nginx.conf <<"EOF"
# Elastic Beanstalk Nginx Configuration File

user  nginx;
worker_processes  1;

error_log  /var/log/nginx/error.log;

pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    access_log    /var/log/nginx/access.log;

    include       /etc/nginx/conf.d/*.conf;
    include       /etc/nginx/sites-enabled/*;
}
EOF
	
	mkdir -p /etc/nginx/sites-available
	mkdir -p /etc/nginx/sites-enabled
else
	error_exit "Unknown nginx distribution" 1
fi

cat > /etc/nginx/sites-available/elasticbeanstalk-nginx-docker-proxy.conf <<EOF
map \$http_upgrade \$connection_upgrade {
	default		"upgrade";
	""			"";
}

server {
	listen $EB_CONFIG_HTTP_PORT;

	location / {
		proxy_pass			http://docker;
		proxy_http_version	1.1;

		proxy_set_header	Connection			\$connection_upgrade;
		proxy_set_header	Upgrade				\$http_upgrade;
		proxy_set_header	Host				\$host;
		proxy_set_header	X-Real-IP			\$remote_addr;
		proxy_set_header	X-Forwarded-For		\$proxy_add_x_forwarded_for;
	}
}
EOF
ln -sf /etc/nginx/sites-available/elasticbeanstalk-nginx-docker-proxy.conf /etc/nginx/sites-enabled/

mkdir -p /var/log/nginx

if is_rhel; then
	chown -R nginx:nginx /var/log/nginx
else
	error_exit "Unknown nginx distribution" 1
fi

service nginx stop
