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

chkconfig_on() {
	# enable cfn-hup and nginx on boot
	chkconfig cfn-hup on
	chkconfig nginx on
}

if ! is_baked docker_packages; then
    echo "Running on unbaked AMI, installing packages."
	yum install -y docker jq nginx sqlite
fi

if ! is_baked docker_start; then
	echo "Running on unbaked AMI, starting docker."
	service docker start
fi

chkconfig_on

