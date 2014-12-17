
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

require 'elasticbeanstalk/exceptions'

module ElasticBeanstalk

    class CommandData
        
        attr_accessor :api_version, :command_name, :request_id, :config_set
        attr_accessor :stage_name, :stage_num
        attr_accessor :resource_name, :data, :execution_data
        attr_accessor :instance_ids
        attr_accessor :cfn_command_name, :invocation_id, :dispatcher_id
        
        def initialize(cmd_data_str, cfn_command_name: nil, invocation_id: nil, dispatcher_id: nil)
            cmd_data_str = Kernel.open(cmd_data_str).read if cmd_data_str.start_with?('http')
            
            @cmd_data = cmd_data_str
            cmd_data = JSON.parse(cmd_data_str)
            @api_version = cmd_data['api_version']
            @command_name = cmd_data['command_name']
            @request_id = cmd_data['request_id']
            @config_set = cmd_data['config_set']
            @stage_name = cmd_data['stage_name']
            @stage_num = cmd_data['stage_num']
            @last_stage = cmd_data['is_last_stage']
            @resource_name = cmd_data['resource_name']
            @data = cmd_data['data']
            @execution_data = cmd_data['execution_data']
            @instance_ids = cmd_data['instance_ids']
            @cfn_command_name = cfn_command_name
            @invocation_id = invocation_id
            @dispatcher_id = dispatcher_id

            raise BeanstalkRuntimeError, %[Missing command name!] unless @command_name
        end
        
        def last_stage?
            @last_stage
        end
        
        def to_s
            @cmd_data
        end
    end
end
