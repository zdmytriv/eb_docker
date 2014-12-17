
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

require 'time'

class Time
    def to_ms
        (self.to_f * 1000).to_i
    end
end


module ElasticBeanstalk

    module Utils

        def self.logger_formatter
            logger_formatter_impl
        end

        def self.logger_formatter_impl
            proc do |severity, datetime, progname, msg|
                @@pid ||= "[#{Process.pid}]"
                log_msg = "[#{datetime.utc.iso8601(3)}] #{severity.ljust(5)} #{@@pid.ljust(7)}"
                if progname.nil? || progname.empty?
                    log_msg = log_msg + " : #{msg}\n"
                else
                    log_msg = log_msg + " - [#{progname}] : #{msg}\n"
                end
                log_msg
            end
        end

    end

end