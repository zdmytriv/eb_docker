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

EB_CONFIG_APP_SOURCE=$(/opt/elasticbeanstalk/bin/get-config container -k source_bundle)
EB_CONFIG_APP_CURRENT=$(/opt/elasticbeanstalk/bin/get-config container -k app_deploy_dir)
EB_SUPPORT_FILES=$(/opt/elasticbeanstalk/bin/get-config container -k support_files_dir)

APP_BUNDLE_TYPE=`file -m $EB_SUPPORT_FILES/beanstalk-magic -b --mime-type $EB_CONFIG_APP_SOURCE`

# User can upload either a zip or simply a Dockerfile
if [ "$APP_BUNDLE_TYPE" = "application/zip" ]; then
	unzip -o -d $EB_CONFIG_APP_CURRENT $EB_CONFIG_APP_SOURCE || error_exit "Failed to unzip source bundle, abort deployment" 1
elif [ "$APP_BUNDLE_TYPE" = "application/x.dockerrun" ]; then
	# jq 1.2 has a bug where parse error will return 0 instead of 1, thus we need the additional grep test
	if cat $EB_CONFIG_APP_SOURCE | jq . && ! cat $EB_CONFIG_APP_SOURCE | jq . 2>&1 | grep -q 'parse error'; then
		cp -f $EB_CONFIG_APP_SOURCE $EB_CONFIG_APP_CURRENT/Dockerrun.aws.json
	else
		error_exit "Failed to parse Dockerrun.aws.json file, abort deployment" 1
	fi
else
	# repeat the JSON test here in case "file" missed anything (e.g. blank lines at beginning of file etc.)
	if cat $EB_CONFIG_APP_SOURCE | jq . && ! cat $EB_CONFIG_APP_SOURCE | jq . 2>&1 | grep -q 'parse error'; then
		cp -f $EB_CONFIG_APP_SOURCE $EB_CONFIG_APP_CURRENT/Dockerrun.aws.json
	else
		cp -f $EB_CONFIG_APP_SOURCE $EB_CONFIG_APP_CURRENT/Dockerfile
	fi
fi
