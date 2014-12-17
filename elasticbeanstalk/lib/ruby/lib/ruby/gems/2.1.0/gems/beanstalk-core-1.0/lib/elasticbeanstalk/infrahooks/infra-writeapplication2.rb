# Beanstalk

#==============================================================================
# Copyright 2014 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Amazon Software License (the "License"). You may not use
# this file except in compliance with the License. A copy of the License is
# located at
#
#       https://aws.amazon.com/asl/
#
# or in the "license" file accompanying this file. This file is distributed on
# an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
# implied. See the License for the specific language governing permissions
# and limitations under the License.
#==============================================================================

#require 'open-uri'

#appsource_url = File.read(Command.appsourceurl_file).chomp
#open(Command.sourcebundle_file, 'wb') do |f|
#    f << open(appsource_url).read
#end #==> Should we add retries?

require 'elasticbeanstalk/cfn-wrapper'

CfnWrapper.run_config_sets(config_sets: 'Infra-WriteApplication2')
