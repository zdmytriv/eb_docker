
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

require 'executor'
require 'shellwords'
require 'elasticbeanstalk/exceptions'
require 'elasticbeanstalk/environment-metadata'

module ElasticBeanstalk
    class CfnWrapper

        def self.run_config_sets(config_sets:, env_metadata: nil)
            env_metadata ||= EnvironmentMetadata.new
            call = "/opt/aws/bin/cfn-init -v -s '#{env_metadata.stack_name}' -r '#{env_metadata.resource}' --region '#{env_metadata.region}' --configsets '#{config_sets}'"
            self.call_cfn_script(call, env_metadata, print_cmd_on_error: false)
        end

        def self.resource_metadata(resource:, env_metadata:)
            metadata_call = "/opt/aws/bin/cfn-get-metadata --region='#{env_metadata.region}' --stack='#{env_metadata.stack_name}' --resource='#{resource}'"
            self.call_cfn_script(metadata_call, env_metadata)
        end

        def self.send_cmd_event(payload:, env_metadata:, escape_payload: true)
            if escape_payload
                payload = Shellwords.escape(payload)
            end
            call = "/opt/aws/bin/cfn-send-cmd-event #{payload}"
            self.call_cfn_script(call, env_metadata, env: ENV)
        end

        def self.elect_cmd_leader(cmd_name:, invocation_id:, instance_id:, env_metadata:, raise_on_error:)
            call = "/opt/aws/bin/cfn-elect-cmd-leader --stack '#{env_metadata.stack_name}' --command-name '#{cmd_name}' --invocation-id '#{invocation_id}' --listener-id '#{instance_id}' --region='#{env_metadata.region}'"
            self.call_cfn_script(call, env_metadata, raise_on_error: raise_on_error)
        end

        def self.call_cfn_script (call, env_metadata, *args)
            call = "#{call} --url #{env_metadata.cfn_url}" if env_metadata.cfn_url
            result = Executor::Exec.sh(call, *args)
        end
    end
end
