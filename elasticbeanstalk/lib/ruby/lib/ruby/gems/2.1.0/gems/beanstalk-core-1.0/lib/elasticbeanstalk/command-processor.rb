
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

require 'open-uri'
require 'json'
require 'tempfile'
require 'logger'
require 'yaml'
require 'thread'

require 'elasticbeanstalk/activity'
require 'elasticbeanstalk/cfn-command-reporter'
require 'elasticbeanstalk/command'
require 'elasticbeanstalk/command-data'
require 'elasticbeanstalk/constants'
require 'elasticbeanstalk/environment-metadata'
require 'elasticbeanstalk/exceptions'
require 'elasticbeanstalk/command-heart-beat'
require 'elasticbeanstalk/utils'

module ElasticBeanstalk
    class CommandProcessor
        @@log_file = '/var/log/eb-commandprocessor.log'
        @@cache_dir='/var/lib/eb-tools/data/stages/'
        
        def self.logger
            @@logger
        end
        
        def self.log_file
            @@log_file
        end

        # Constructor to help in unit-testing
        def initialize(cache_dir: @@cache_dir, env_metadata: nil, logger: logger)
            logger_file = File.open(@@log_file, 'a')
            logger_file.sync = true
            @@logger = logger || Logger.new(logger_file,
                                            shift_age: Constants::LOG_SHIFT_AGE,
                                            shift_size: Constants::LOG_SHIFT_SIZE)
            @@logger.formatter = Utils.logger_formatter
            @cache_dir = cache_dir.end_with?('/') ? cache_dir : "#{cache_dir}/"
            @env_metadata = env_metadata || EnvironmentMetadata.new(logger: @@logger)
        end
        
        def execute!(cmd_data)
            execute_command(cmd_data) do
                cmd_result = nil
                Activity.create(name: cmd_data.command_name) do
                    @@logger.info("Executing command: #{cmd_canonical_name(cmd_data)}...")
                    cmd_result = Command.run(cmd_data, logger: @@logger)

                    if cmd_result.status == 'SUCCESS'
                        @@logger.info("Command #{cmd_canonical_name(cmd_data)} succeeded!")
                        "Command #{cmd_canonical_name(cmd_data)} succeeded."
                    else
                        @@logger.error("Command #{cmd_canonical_name(cmd_data)} failed!")
                        "Command #{cmd_canonical_name(cmd_data)} failed."
                    end
                end
                cmd_result
            end
        end

        def execute_command?(cmd_data)
            @@logger.debug("Checking if the command processor should execute.")
            instance_command_check = check_instance_command(cmd_data.instance_ids)
            is_valid_stage = valid_stage?(cmd_data.stage_num, cmd_data.request_id)
            instance_command_check && is_valid_stage
        end

        private
        def execute_command(cmd_data)
            @@logger.info("Received command #{cmd_canonical_name(cmd_data)}: #{cmd_data}")
            
            #PREP
            if !execute_command?(cmd_data)
                @@logger.warn("Command processor shouldn't execute command.. Returning")
                raise BeanstalkRuntimeError, %[Shouldn't execute this stage of command!]
            end

            @@logger.info("Command processor should execute command.")
            store_stage_executed(cmd_data.request_id, cmd_data.stage_num, cmd_data.last_stage?)
            tmp_events_file = events_file

            # start reporting thread
            # exit_signal_queue = Queue.new
            # report_thread = Thread.new() do
            #      ElasticBeanstalk::CommandHeartBeatReporter.new(exit_signal_queue: exit_signal_queue, logger: @@logger)
            # end

            #ENACT
            cmd_result = yield
            
            #POST
            # wait for reporter exit
            # exit_signal_queue.push(true)
            # report_thread.wakeup
            # report_thread.join

            cmd_result.process_events(tmp_events_file.path)
            @@logger.info("Command processor returning results: \n#{CfnCommandReporter.report(cmd_result)}")
            cmd_result
        end


        private
        def check_instance_command(cmd_instance_ids)
            instance_id = @env_metadata.instance_id
            @@logger.debug("Checking whether the command is applicable to instance (#{instance_id})..")
            if cmd_instance_ids && cmd_instance_ids.length > 0 && !cmd_instance_ids.include?(instance_id)
                @@logger.warn("Command should not be executed on this instance (#{instance_id}). Exiting..") 
                return false
            end
            @@logger.info("Command is applicable to this instance (#{instance_id})..")
            return true
        end

        private
        def valid_stage?(current_stage, request_id)
            @@logger.debug("Checking if the received command stage is valid..")

            case current_stage
            when nil
                @@logger. info("No stage_num in command. Valid stage..")
                return true
            when 0
                @@logger.info("Stage_num=#{current_stage.to_s}. Valid stage..")
                return true
            else
                @@logger.debug("Stage_num=#{current_stage.to_s}. Checking previous stage..")
                prev_stage = read_previous_stage(request_id)

                if !prev_stage
                    @@logger.warn("Could not find a previous stage for request id: #{request_id}. Invalid stage..")
                    return false
                end
            
                if prev_stage == current_stage - 1
                    @@logger.info("Previous stage (#{prev_stage}) is one less that current stage (#{current_stage}). Valid stage..")
                    return true
                end
            
                @@logger.warn("Previous stage (#{prev_stage}) is not one less that current stage (#{current_stage}). Invalid stage..")
                return false
            end
        end

        private
        def read_previous_stage(request_id)
            stage_file = "#{@cache_dir}#{request_id}"
            @@logger.debug("Opening previous stage file #{stage_file}..")

            if !File.exists?(stage_file)
                @@logger.debug("Previous stage file does not exist. Return nil..")
                return nil
            end
            
            contents = File.read(stage_file)
            @@logger.debug("Previous stage file contains: #{contents}.")
            if /\A\d+\Z/ =~ contents
                @@logger.debug("Returning #{contents}..")
                return contents.to_i
            else
                @@logger.debug("Previous stage file does not contain a valid integer. Returning nil..")
                return nil
            end
        end


        private
        def store_stage_executed(request_id, stage_num, is_last_stage)
            @@logger.debug("Storing current stage..")
            if stage_num == nil
                @@logger.debug("Stage_num does not exist. Not saving null stage. Returning..")
                return 
            end
            
            if is_last_stage
                @@logger.info("This was last stage for the command. Removing saved stage info for request..")
                FileUtils.rm("#{@cache_dir}#{request_id}", :force => true)
                return
            end

            @@logger.info("Saving stage #{stage_num}..")
            FileUtils.mkdir_p(@cache_dir)
            File.open("#{@cache_dir}#{request_id}", 'w') do |f|
                f.write(stage_num.to_s)
            end
        end


        private
        def events_file
            tempfile = Tempfile.new('eventsfile')
            ENV['EB_EVENT_FILE'] = tempfile.path
            tempfile
        end

        private
        def cmd_canonical_name(cmd_data)
            name = cmd_data.command_name
            if cmd_data.stage_num
                name = name + %[(stage #{cmd_data.stage_num})]
            end
            name
        end
    end
    
end
