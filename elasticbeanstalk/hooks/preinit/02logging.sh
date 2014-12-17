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

/opt/elasticbeanstalk/bin/log-conf   -n applogs -l'/var/log/eb-docker/containers/eb-current-app/*' -r size=1M,rotate=5
/opt/elasticbeanstalk/bin/log-conf   -n nginx -l'/var/log/nginx/*' -r size=1M,rotate=5
/opt/elasticbeanstalk/bin/log-conf   -n docker -l'/var/log/docker-events.log,/var/log/docker-ps.log' -r size=1M,rotate=5
/opt/elasticbeanstalk/bin/log-conf   -n docker -l'/var/log/rotated/docker-events.log*,/var/log/rotated/docker-ps.log*' -t bundlelogs

# docker daemon log
/opt/elasticbeanstalk/bin/log-conf   -n dockerdaemon -l'/var/log/docker' -t taillogs,systemtaillogs,publishlogs -r size=1M,rotate=5
/opt/elasticbeanstalk/bin/log-conf   -n dockerdaemon -l'/var/log/docker*' -t bundlelogs	
