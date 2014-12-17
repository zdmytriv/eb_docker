
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
require 'pathname'

module ElasticBeanstalk
    class Executable
        attr_accessor :path
    
        def self.create(path)
            if beanstalk_executable?(path)
                BeanstalkExecutable.new(path)
            else
                UserExecutable.new(path)
            end
        end
        
        def self.executable?(file_path)
            file_name = file_path.split('/')[-1]
            is_hidden = /^([\.].*|.+\.bak|.+\.tmp)$/ =~ file_name
            
            is_executable = File.executable?(file_path)
            
            !File.directory?(file_path) && is_executable && !is_hidden
        end
        
        def initialize(path)
            @path = path
        end
        
        private
        def self.beanstalk_executable?(path)
            file_ext = Pathname(path).extname
            first_line = File.open(path) { |f| f.first }
            file_ext == '.rb' && first_line.chop == "# Beanstalk"
        end
    end
    
    class BeanstalkExecutable < Executable
        def execute!
            file = File.open(@path)
            self.instance_eval(file.read, file.path, 1)
        end
    end
    
    class UserExecutable < Executable
        include Executor
        def execute!
            sh(@path)
        end
    end
end

