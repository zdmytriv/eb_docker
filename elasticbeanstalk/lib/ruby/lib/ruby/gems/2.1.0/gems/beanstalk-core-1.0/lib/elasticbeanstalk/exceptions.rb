
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

module ElasticBeanstalk
    class BeanstalkRuntimeError < RuntimeError; end

    class ActivityFatalError < RuntimeError;
        # msg is the exception root cause
        # activity_error_msg is the activity failure reason, e.g. timeout, fail, etc.
        attr_accessor :activity_error_msg, :activity_path

        def initialize (msg:, activity_error_msg: "", activity_path: "")
            super(msg)
            @activity_error_msg = activity_error_msg
            @activity_path = activity_path
        end

        def message
            "[#{@activity_path}] #{super}"
        end
    end

    class ActivityTimeoutError < ActivityFatalError; end
    class ActivityInternalError < ActivityFatalError; end


    # Dump error message and stack trace from exception
    # full_trace: when set to false only root cause exception trace is dumped, otherwise trace of every
    # nested exception is dumped
    def self.format_exception(e, full_trace: false)
        first_trace = e.backtrace.first
        backtrace = e.backtrace.drop(1).collect { |i| "\tfrom #{i}"}.join("\n")
        message = %[#{e.message} (#{e.class})\n\tat #{first_trace}\n]
        if full_trace || e.cause.nil?
            message = %[#{message}#{backtrace}]
        else
            message =  %[#{message}\t...]
        end

        while e.cause
            first_trace = e.cause.backtrace.first
            backtrace = e.cause.backtrace.drop(1).collect { |i| "\tfrom #{i}"}.join("\n")
            message = %[#{message}\ncaused by: #{e.cause.message} (#{e.cause.class})\n\tat #{first_trace}\n]
            if ! full_trace && e.cause.cause
                message = %[#{message}\t...]
            else
                message = %[#{message}#{backtrace}]
            end

            e = e.cause
        end
        %[#{message}\n\n]
    end

end
