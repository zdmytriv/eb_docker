
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
require 'pathname'
require 'elasticbeanstalk/activity'
require 'elasticbeanstalk/executable'

module ElasticBeanstalk
    class HookDirectoryExecutor

        def run!(path)
            executables(path).each do |executable|
                filename = Pathname.new(executable.path).basename
                Activity.create(name: filename) do
                    executable.execute!
                end
            end
            "Successfully execute directory: #{path}."
        end

        def executables(path)
            Dir.glob("#{path}/*").select {|file_path| Executable.executable?(file_path)}.sort.collect { |file_path| Executable.create(file_path) }
        end
    end
end
