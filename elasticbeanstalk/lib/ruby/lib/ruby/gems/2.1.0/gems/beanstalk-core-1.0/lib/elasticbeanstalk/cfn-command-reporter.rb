
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

require 'elasticbeanstalk/constants'
require 'elasticbeanstalk/event'

module ElasticBeanstalk
    class CfnCommandReporter

        API_VERSION = '1.0'
        MAX_EVENT_MSG_SIZE = 512
        MAX_OVERALL_RESULT_SIZE = 1024

        def self.report(cmd_result)

            # copy and truncate event messages when applicable
            events = cmd_result.events.collect do |event| 
                ne = event.clone
                ne.msg = ne.msg[0 .. MAX_EVENT_MSG_SIZE - 1]
                ne
            end

            results = {"status" => cmd_result.status,
                       "msg" => cmd_result.msg[0 .. MAX_OVERALL_RESULT_SIZE],
                       "returncode" => cmd_result.return_code,
                       "events" => events}

           if ! cmd_result.config_sets.nil? && ! cmd_result.config_sets.empty?
              results["config_set"] = cmd_result.config_sets 
           end

            overall_result = {"status" => cmd_result.status,
                              "api_version" => API_VERSION,
                              "truncated" => 'false',
                              "results" => [results]}

            self.truncate_events(overall_result, :WARN) unless events.empty?
            result_str = overall_result.to_json

            if result_str.length > MAX_OVERALL_RESULT_SIZE
                diff = result_str.length - MAX_OVERALL_RESULT_SIZE
                if diff > results["msg"].length
                    results["msg"] = ""
                else
                    results["msg"] = results["msg"][0..results["msg"].length-diff-1]
                end
                overall_result['truncated'] = 'true'
            end
            
            self.truncate_events(overall_result, :FATAL) unless events.empty?

            events.sort! { |e1, e2| e1.timestamp <=> e2.timestamp }
            overall_result.to_json
        end
        
        def self.truncate_events(overall_result, truncation_severity)
            events = overall_result["results"][0]["events"]
            result_str = overall_result.to_json

            # truncate events if message is too large
            if result_str.length > MAX_OVERALL_RESULT_SIZE && events.size > 0
                events.sort! # sort events based on severity

                while events.size > 0 && result_str.length > MAX_OVERALL_RESULT_SIZE && Event::severity_map[events[0].severity] <= Event::severity_map[truncation_severity]
                    overall_result['truncated'] = 'true'
                    events.delete_at(0)
                    result_str = overall_result.to_json
                end
            end
        end
        

    end
end


