
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

require 'logger'
require 'open-uri'

require 'elasticbeanstalk/activity'
require 'elasticbeanstalk/addon'
require 'elasticbeanstalk/cfn-wrapper'
require 'elasticbeanstalk/command-result'
require 'elasticbeanstalk/environment-metadata'
require 'elasticbeanstalk/exceptions'
require 'elasticbeanstalk/executable'
require 'elasticbeanstalk/hook-directory-executor'

module ElasticBeanstalk

    class Command
        @@hooks_root = "/opt/elasticbeanstalk/hooks/"
        @@deploy_config_dir = '/opt/elasticbeanstalk/deploy/configuration/'
        @@appsourceurl_file = File.join(@@deploy_config_dir, 'appsourceurl')
        @@containerconfig_file = File.join(@@deploy_config_dir, 'containerconfiguration')
        @@sourcebundle_dir = '/opt/elasticbeanstalk/deploy/appsource'
        @@sourcebundle_file = '/opt/elasticbeanstalk/deploy/appsource/source_bundle'

        @@infra_file_map = {
            "embeddedprebuild" => "infra-embeddedprebuild.rb",
            "embeddedpostbuild" => "infra-embeddedpostbuild.rb",
            "cleanebextensions" => "infra-cleanebextensionsdir.rb",
            "writeapplication1" => "infra-writeapplication1.rb",
            "writeapplication2" => "infra-writeapplication2.rb",
            "writeruntimeconfig" => "infra-writeruntimeconfig.rb",
        }
        
        def self.run(cmd_data, logger: Logger.new(File.open(File::NULL, "w")))
            # Currently we always refresh metadata for each command we received because of addons
            env_metadata = EnvironmentMetadata.new(logger: logger)
            env_metadata.refresh(request_id: cmd_data.request_id, resource: cmd_data.resource_name)
            logger.debug("Refreshed environment metadata.")

            command_defs = env_metadata.command_definitions
            addon_manager = ElasticBeanstalk::AddonManager.new(env_metadata: env_metadata, logger: logger)
            command_defs = addon_manager.update_command_def(command_defs)

            command_def = command_defs.fetch(cmd_data.command_name, nil)
            if command_def
                command = ContainerDefinitionCommand.new(name: cmd_data.command_name,
                                                         definition: command_def,
                                                         addon_manager: addon_manager,
                                                         env_metadata: env_metadata,
                                                         logger: logger)
            else
                command = TemplateCommand.new(env_metadata: env_metadata, logger: logger)
            end
            command.execute!(cmd_data)
        end
        
        def self.deploy_config_dir
            @@deploy_config_dir
        end
        
        def self.appsourceurl_file
            @@appsourceurl_file
        end
        
        def self.containerconfig_file
            @@containerconfig_file
        end
        
        def self.sourcebundle_dir
            @@sourcebundle_dir
        end
        
        def self.sourcebundle_file
            @@sourcebundle_file
        end

        def initialize(env_metadata:, logger:)
            @logger = logger
            @env_metadata = env_metadata
        end

        private
        def set_environment_variables(cmd_data)
            @logger.debug("Setting environment variables..")
            ENV['EB_RESOURCE_NAME'] = cmd_data.resource_name if cmd_data.resource_name
            ENV['EB_COMMAND_DATA'] = cmd_data.data if cmd_data.data
            ENV['EB_EXECUTION_DATA'] = cmd_data.execution_data if cmd_data.execution_data
            ENV['EB_REQUEST_ID'] = cmd_data.request_id if cmd_data.request_id
        end

        private
        def elect_leader (cmd_data)
            if @env_metadata.leader?(cmd_data)
                ENV['EB_IS_COMMAND_LEADER'] = 'true'
            else
                ENV['EB_IS_COMMAND_LEADER'] = 'false'
            end
        end
    end


    class ContainerDefinitionCommand < Command

        STAGES_KEY = 'stages'

        ACTION_INFRA = 'infra'
        ACTION_HOOK = 'hook'
        ACTION_SH = 'sh'

        def initialize(name:, definition:, addon_manager:, env_metadata:,
                hooks_root: @@hooks_root, logger: Logger.new(File.open(File::NULL, "w")))
            super(env_metadata: env_metadata, logger: logger)
            @name = name
            @addon_manager = addon_manager

            @stages = definition.fetch(STAGES_KEY).collect do |stage_hash|
                Stage.new(stage_hash)
            end
            @logger.debug("Loaded definition of Command #{@name}.")

            @hooks_root = hooks_root
            @hooks_root = "#{@hooks_root}/" unless @hooks_root.end_with?('/')
        end

        def execute!(cmd_data)
            @cmd_data = cmd_data
            cmd_result = CommandResult.new
            @logger.info("Executing command #{@name} activities...")
            begin
                set_environment_variables(cmd_data)

                cur_stage_index = cmd_data.stage_num ? cmd_data.stage_num : 0
                end_stage_index = cmd_data.stage_num ? cmd_data.stage_num : stage_count - 1

                if cur_stage_index == 0 # if this the first stage
                    @logger.info("Running AddonsBefore for command #{@name}...")
                    Activity.create(name: "AddonsBefore") do
                        @addon_manager.run_addons_before(cmd_name: @name)
                    end
                end

                @logger.debug("Running stages of Command #{@name} from stage #{cur_stage_index} to stage #{end_stage_index}...")
                while cur_stage_index <= end_stage_index
                    exec_stage(cmd_data:cmd_data, cur_stage_index: cur_stage_index)
                    cur_stage_index += 1
                end

                if cur_stage_index == stage_count   # if this the last stage
                    @logger.info("Running AddonsAfter for command #{@name}...")
                    Activity.create(name: "AddonsAfter") do
                        @addon_manager.run_addons_after(cmd_name: @name)
                    end
                end

                cmd_result.status = 'SUCCESS'
                cmd_result.return_code = 0
            rescue Exception => e
                cmd_result.msg = e.message
                @logger.error("Command execution failed: #{ElasticBeanstalk.format_exception(e)}")
                cmd_result.status = 'FAILURE'
                cmd_result.return_code = 1
            end
            cmd_result
        end

        private
        def infrahook_dir
            File.join(File.dirname(File.expand_path(__FILE__)), "infrahooks")
        end

        private
        def stage_count
            @stages.length
        end

        private
        def stage (index:)
            @stages.fetch(index)
        end

        private
        def exec_stage(cmd_data:, cur_stage_index:)
            @logger.info("Running stage #{cur_stage_index} of command #{@name}...")
            cur_stage = stage(index: cur_stage_index)

            if cur_stage.need_leader?
                elect_leader(cmd_data)
            end

            Activity.create(name: cur_stage.name) do
                @logger.debug("Loaded #{cur_stage.actions.length} actions for stage #{cur_stage_index}.")

                cur_stage.actions.each_with_index do |action, index|
                    @logger.info("Running #{index + 1} of #{cur_stage.actions.length} actions: #{action.name}...")
                    Activity.create(name: action.name) do
                        case action.type
                            when ACTION_INFRA
                                filename = @@infra_file_map.fetch(action.value)
                                BeanstalkExecutable.new(File.join(infrahook_dir, filename)).execute!
                            when ACTION_HOOK
                                HookDirectoryExecutor.new.run!(File.join(@hooks_root, action.value))
                            when ACTION_SH
                                Executor::Exec.sh(action.value)
                            else
                                raise BeanstalkRuntimeError, "Not recognized action type: #{action.type}."
                        end
                    end
                end
                "Command #{@name} stage #{cur_stage_index} completed."
            end
        end

        class Stage
            NAME_KEY = 'name'
            LEADER_ELECTION = 'leader_election'
            ACTIONS_KEY = 'actions'

            attr_reader :name, :actions

            def initialize (args)
                @name = args.fetch(NAME_KEY)

                leader_elect = args.fetch(LEADER_ELECTION, false)
                if leader_elect == true ||
                    (leader_elect.is_a?(String) &&  leader_elect.downcase == 'true')
                    @leader_election = true
                else
                    @leader_election = false
                end

                @actions = args.fetch(ACTIONS_KEY).collect do |x|
                    Action.new(x)
                end
            end

            def need_leader?
                @leader_election
            end
        end

        class Action
            NAME_KEY = 'name'
            TYPE_KEY = 'type'
            VALUE_KEY = 'value'

            attr_reader :name, :type, :value

            def initialize (args)
                @name = args.fetch(NAME_KEY)
                @type = args.fetch(TYPE_KEY)
                @value = args.fetch(VALUE_KEY)
            end
        end
    end


    class TemplateCommand < Command
        def initialize(env_metadata:, logger: Logger.new(File.open(File::NULL, "w")))
            super(env_metadata: env_metadata, logger: logger)
        end

        def execute!(cmd_data)
            cmd_result = CommandResult.new
            begin
                set_environment_variables(cmd_data)

                Activity.create(name: "cfn-init-call") do
                    config_sets = @env_metadata.command_config_sets(cmd_data)
                    CfnWrapper.run_config_sets(env_metadata: @env_metadata, config_sets: config_sets.join(","))
                end
                cmd_result.status = 'SUCCESS'
                cmd_result.return_code = 0
            rescue Exception => e
                @logger.error("Command execution failed: #{e.message}")
                cmd_result.status = 'FAILURE'
                cmd_result.return_code = 2
                cmd_result.msg = e.message
            end
            cmd_result
        end
    end
end
