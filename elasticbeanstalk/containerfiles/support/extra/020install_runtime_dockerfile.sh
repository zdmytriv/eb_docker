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

EB_SUPPORT_FILES=$(/opt/elasticbeanstalk/bin/get-config container -k support_files_dir)
EB_CONFIG_APP_CURRENT=$(/opt/elasticbeanstalk/bin/get-config container -k app_deploy_dir)

. /opt/elasticbeanstalk/hooks/common.sh
. $EB_SUPPORT_FILES/extra/runtime.config

# if the bundle does not have a Dockerfile, inject runtime Dockerfile
if [ ! -f $EB_CONFIG_APP_CURRENT/Dockerfile ]; then
	cp $EB_RUNTIME_DOCKERFILE $EB_CONFIG_APP_CURRENT/Dockerfile
fi

# make sure the runtime image is correct (in case customer provides a Dockerfile)
FROM_IMAGE=`cat $EB_CONFIG_APP_CURRENT/Dockerfile | grep -i ^FROM | head -n 1 | awk '{ print $2 }' | sed $'s/\r//'`
if [ "$FROM_IMAGE" != "$EB_RUNTIME_IMAGE" ]; then
	error_exit "Invalid runtime Docker image. Expecting: $EB_RUNTIME_IMAGE, was: $FROM_IMAGE. Abort deployment." 1
fi

# inject default logging path in to Dockerrun.aws.json (if not explictly overridden by customer)
EB_CONFIG_DOCKER_LOG_CONTAINER_DIR=`cat $EB_CONFIG_APP_CURRENT/Dockerrun.aws.json | jq -r .Logging`
if [ -z "$EB_CONFIG_DOCKER_LOG_CONTAINER_DIR" ] || [ "$EB_CONFIG_DOCKER_LOG_CONTAINER_DIR" = "null" ]; then
	if [ -f $EB_CONFIG_APP_CURRENT/Dockerrun.aws.json ]; then
		# append Logging attribute
		cat $EB_CONFIG_APP_CURRENT/Dockerrun.aws.json | jq ". + { \"Logging\": \"$EB_RUNTIME_DEFAULT_LOG_DIR\" }" > $EB_CONFIG_APP_CURRENT/Dockerrun.aws.json.new
		mv $EB_CONFIG_APP_CURRENT/Dockerrun.aws.json.new $EB_CONFIG_APP_CURRENT/Dockerrun.aws.json
	else
		# no existing Dockerrun.aws.json, just generate a new one
		cat > $EB_CONFIG_APP_CURRENT/Dockerrun.aws.json <<EOF
{
	"AWSEBDockerrunVersion": "1",
	"Logging": "$EB_RUNTIME_DEFAULT_LOG_DIR"
}
EOF
	fi
fi
