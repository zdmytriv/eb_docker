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

EB_CONFIG_DOCKER_PORT_FILE=$(/opt/elasticbeanstalk/bin/get-config container -k port_file)

EB_CONFIG_DOCKER_STAGING_APP_FILE=$(/opt/elasticbeanstalk/bin/get-config container -k app_staging_file)
EB_CONFIG_DOCKER_CURRENT_APP_FILE=$(/opt/elasticbeanstalk/bin/get-config container -k app_deploy_file)

EB_CONFIG_DOCKER_IMAGE_STAGING=$(/opt/elasticbeanstalk/bin/get-config container -k staging_image)
EB_CONFIG_DOCKER_IMAGE_CURRENT=$(/opt/elasticbeanstalk/bin/get-config container -k deploy_image)

EB_CONFIG_HTTP_PORT=$(/opt/elasticbeanstalk/bin/get-config container -k instance_port)

# now the STAGING container is built and running, flip nginx to the new container
EB_CONFIG_NGINX_UPSTREAM_IP=$(docker inspect `cat $EB_CONFIG_DOCKER_STAGING_APP_FILE` | jq -r .[0].NetworkSettings.IPAddress)
EB_CONFIG_NGINX_UPSTREAM_PORT=`cat $EB_CONFIG_DOCKER_PORT_FILE`

# set up nginx
cat > /etc/nginx/conf.d/elasticbeanstalk-nginx-docker-upstream.conf <<EOF
upstream docker {
	server $EB_CONFIG_NGINX_UPSTREAM_IP:$EB_CONFIG_NGINX_UPSTREAM_PORT;
	keepalive 256;
}
EOF
service nginx restart || error_exit "Failed to start nginx, abort deployment" 1

# stop and delete "current"
if [ -f $EB_CONFIG_DOCKER_CURRENT_APP_FILE ]; then
	EB_CONFIG_DOCKER_CURRENT_APP=`cat $EB_CONFIG_DOCKER_CURRENT_APP_FILE | cut -c 1-12`
	echo "Stopping current app container: $EB_CONFIG_DOCKER_CURRENT_APP..."

	if docker ps | grep -q $EB_CONFIG_DOCKER_CURRENT_APP; then
		stop_upstart_service eb-docker
	fi

	if docker ps | grep -q $EB_CONFIG_DOCKER_CURRENT_APP; then
		docker kill $EB_CONFIG_DOCKER_CURRENT_APP
	fi

	if docker ps -a | grep -q $EB_CONFIG_DOCKER_CURRENT_APP; then
		docker rm $EB_CONFIG_DOCKER_CURRENT_APP
	fi

	EB_CONFIG_DOCKER_IMAGE_ID_STAGING=`docker images | grep ^$EB_CONFIG_DOCKER_IMAGE_STAGING | awk '{ print $3 }'`
	EB_CONFIG_DOCKER_IMAGE_ID_CURRENT=`docker images | grep ^$EB_CONFIG_DOCKER_IMAGE_CURRENT | awk '{ print $3 }'`

	# this check is necessary since due to caching/config deploy these two could be the same image
	if [ "$EB_CONFIG_DOCKER_IMAGE_ID_STAGING" != "$EB_CONFIG_DOCKER_IMAGE_ID_CURRENT" ]; then
		docker rmi $EB_CONFIG_DOCKER_IMAGE_CURRENT || true
	fi
fi

# flip "STAGING" to "current"
echo "Making STAGING app container current..."
EB_CONFIG_DOCKER_IMAGE_ID_STAGING=`docker images | grep ^$EB_CONFIG_DOCKER_IMAGE_STAGING | awk '{ print $3 }'`
docker tag $EB_CONFIG_DOCKER_IMAGE_ID_STAGING $EB_CONFIG_DOCKER_IMAGE_CURRENT
docker rmi $EB_CONFIG_DOCKER_IMAGE_STAGING

mv $EB_CONFIG_DOCKER_STAGING_APP_FILE $EB_CONFIG_DOCKER_CURRENT_APP_FILE

# start monitoring it
start_upstart_service eb-docker

trace "Docker container `cat $EB_CONFIG_DOCKER_CURRENT_APP_FILE | cut -c 1-12` is running $EB_CONFIG_DOCKER_IMAGE_CURRENT."
