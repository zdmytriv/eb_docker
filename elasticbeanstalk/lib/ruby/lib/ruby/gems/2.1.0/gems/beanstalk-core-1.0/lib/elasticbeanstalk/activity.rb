
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
require 'timeout'

require 'elasticbeanstalk/constants'
require 'elasticbeanstalk/exceptions'
require 'elasticbeanstalk/utils'

module ElasticBeanstalk

    class Activity

        class Timeout < Timeout::Error; end

        class ActivityRecord
            attr_accessor :timestamp, :message

            def initialize (timestamp:, message:)
                @timestamp = timestamp
                @message = message
            end

            def to_s
                "#{@timestamp} - #{@message}"
            end
        end

        #
        # Activity is a uniform interface that wraps actions, so the complete execution sequence including output
        # timetstamp, metrics, etc. can be logged easily and uniformly. It also implements retry and timeout logic.
        #
        #
        # === Examples ===
        #
        # ElasticBeanstalk::Activity.create(name: 'MyActivity', retries: 1) do
        #     "run activity"
        # end
        #
        #
        # ElasticBeanstalk::Activity.create(name: 'LaunchMissile') do
        #     ElasticBeanstalk::Activity.create(name: 'Fill fuel') do
        #         "Fuel in."
        #     end
        #     ElasticBeanstalk::Activity.create(name: 'Count down') do
        #         "3 2 1"
        #     end
        #     ElasticBeanstalk::Activity.create(name: 'Ignition') do
        #         "Launch"
        #     end
        #
        #     "Missile Launched."
        # end


        # Default retry config
        DEFAULT_RETRIES = 0 # no retry
        DEFAULT_RETRY_EXCEPTIONS = [RuntimeError] # retry when RuntimeError is raised

        # Default timeout config
        DEFAULT_TIMEOUT = 0   # no timeout

        # Logging config
        @@logfile_pathname = '/var/log/eb-activity.log'      # default log file pathname
        @@logfile_open_mod = 'a'    # append to existing log file
        @@logger_instance = nil

        @@activity_history = []     # list of past and current activities timestamps

        attr_reader :name
        private_class_method :new

        #
        def initialize (name:, timeout: DEFAULT_TIMEOUT,
            retries: DEFAULT_RETRIES, retry_exceptions: DEFAULT_RETRY_EXCEPTIONS)
            @name = name
            @retries = retries
            @retry_exceptions = retry_exceptions
            @timeout = timeout
            activity_stack << self # append current activity to stack
        end


        #
        # Create an activity instance and run it
        #
        # * +name+ Activity name.
        # * +timeout+ Activity timeout limit in second. Activity running longer than timeout will be terminated.
        #   Default is 0 (no timeout).
        # * +retries+ How many times Activity can be retried when it fails for exceptions defined in retry_exceptions.
        #   Default is 0 (no retry).
        # * +retry_exceptions+ List of Exception types that Activity could retry upon. Default is [RuntimeError].
        def self.create (*args, &block)
            activity = new(*args)
            activity.instance_eval do
                timeout_exec(&block)
            end
        end


        # ==============================================
        # Private methods
        # ==============================================

        # Execute block with retries in time box. Timing out will be disabled if @timeout is set to 0.
        private
        def timeout_exec(&block)
            begin
                self.class.logger.info(activity_path){"Starting activity..."}
                @@activity_history << ActivityRecord.new(timestamp: Time.now, message: "Activity [#{activity_path}] started.")
                if @timeout == 0
                    result = exec(&block)
                else
                    timeout(@timeout) do
                        result = exec(&block)
                    end
                end

                result = format_result(result)
                if result
                    self.class.logger.info(activity_path){"Completed activity. Result:\n#{result}"}
                else
                    self.class.logger.info(activity_path){"Completed activity."}
                end
                @@activity_history << ActivityRecord.new(timestamp: Time.now, message: "Activity [#{activity_path}] completed.")

                return result

            rescue ::Timeout::Error
                msg = %[Activity timed out after #{@timeout} seconds.]
                self.class.logger.info(activity_path){msg}
                @@activity_history << ActivityRecord.new(timestamp: Time.now, message: "Activity [#{activity_path}] timed out.")
                raise ActivityTimeoutError.new(msg: msg, activity_error_msg: 'Activity timed out.', activity_path: activity_path)

            rescue ActivityFatalError => e
                self.class.logger.info(activity_path){e.activity_error_msg}
                raise

            rescue => e
                self.class.logger.info(activity_path){"Activity has unexpected exception, because: #{ElasticBeanstalk.format_exception(e)}"}
                @@activity_history << ActivityRecord.new(timestamp: Time.now, message: "Activity [#{activity_path}] internal failure.")
                raise ActivityInternalError.new(msg: e.message, activity_error_msg: 'Activity internal failure.', activity_path: activity_path)

            ensure
                activity_stack.pop   # pop out current activity from stack
            end
        end


        # Execute block until reaching retry limit
        private
        def exec(&block)
            retry_count = 0
            begin
                block.call

            rescue ActivityFatalError => e
                raise
            rescue *@retry_exceptions => e
                # Log stack trace
                stack_trace = ElasticBeanstalk.format_exception(e)
                self.class.logger.info(activity_path){"Activity execution failed, because: #{stack_trace}"}

                # Retry if allows retry and not reaches limit yet
                if retry_count < @retries
                    retry_count += 1
                    self.class.logger.info(activity_path){"Retrying #{retry_count} of #{@retries}..."}
                    @@activity_history << ActivityRecord.new(timestamp: Time.now, message: "Activity [#{activity_path}] retrying.")
                    retry
                elsif @retries > 0
                    self.class.logger.info(activity_path){"Reached activity retry limit of #{@retries}."}
                end

                @@activity_history << ActivityRecord.new(timestamp: Time.now, message: "Activity [#{activity_path}] failed.")
                raise ActivityFatalError.new(msg: e.message, activity_error_msg: 'Activity failed.', activity_path: activity_path)
            end
        end


        # Lazy load logger instances to allow logger parameter overridden
        private
        def self.logger
            if @@logger_instance.nil?
                logger_file = File.open(@@logfile_pathname, @@logfile_open_mod)
                logger_file.sync = true
                @@logger_instance = Logger.new(logger_file,
                                               shift_age: Constants::LOG_SHIFT_AGE,
                                               shift_size: Constants::LOG_SHIFT_SIZE)
                @@logger_instance.formatter = Utils.logger_formatter
            end
            @@logger_instance
        end


        # Convert activity name stack to a string path
        private
        def activity_path
            name_array = activity_stack.collect(&:name)
            name_array.join('/')
        end

        #  activity_stack tracks activity hierarchy
        private
        def activity_stack
            Thread.current[:activity_stack] ||= []
        end


        private
        def format_result(result)
            result ||= ''
            result = '  ' + result.to_s
            if result.strip.empty?
                nil
            else
                result.gsub(/\n/, "\n  ")
            end
        end

    end

end
