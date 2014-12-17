
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

require 'set'
require 'fileutils'
require 'pathname'

require 'elasticbeanstalk/exceptions'

module ElasticBeanstalk
    class LogConfManager        
        attr_accessor :log_files
        attr_accessor :log_rotate_hash
        
        # Class method to allow executing blocks on a newly created log conf manager.
        # You don't need to call write in the block since it is automatically called at the end of the create method.
        #
        # === Examples
        # 
        # ElasticBeanstalk::LogConfManager.create('base', base_dir: '/opt/elasticbeanstalk') { |obj|
        #     obj.add('/var/log/httpd/*')
        #     obj.log_rotate_hash[:size] = '100M'
        #     obj.log_rotate_hash[:compress] = ''
        #     obj.log_rotate_hash[:create] = 'create'
        # }
        # In the previous example, the size of the log rotation was altered and this new size will apply to any publish logs added to this manager.
        # Furthermore, the 'compress' option was cleared out and 'create' option was added.
        #
        # === Attributes
        #
        # * +base_dir+ EB root directory where the conf directories are set up (/opt/elasticbeanstalk)
        # * +name+ Name of the conf file to write to. '.conf' is appended to it during a write.
        #
        def self.create(*args)
            manager = self.new(*args)
            yield manager
            manager.write
        end    
    
        # Initializes the LogConfManager by setting up the logging conf directories.
        # Default log rotation options are also set in @log_rotate_hash,
        # Note that a '.conf' is appended to the given name.
        #
        # === Examples
        # 
        #   ElasticBeanstalk::LogConfManager.new('base', base_dir: '/opt/elasticbeanstalk')
        #
        # === Attributes
        #
        # * +base_dir+ EB root directory where the conf directories are set up (/opt/elasticbeanstalk)
        # * +name+ Name of the conf file to write to. '.conf' is appended to it during a write.
        #
        def initialize(name, base_dir: '/opt/elasticbeanstalk', logrotateconf_dir: '/etc/logrotate.d',
                hourly_cron_dir: '/etc/cron.hourly', logrotate_subdir: 'rotated')
            @conf_file = name
            @base_dir = base_dir
            @logrotateconf_dir = logrotateconf_dir
            @hourly_cron_dir = hourly_cron_dir
            @logrotate_subdir = logrotate_subdir
            FileUtils.mkdir_p "#{@base_dir}/tasks/taillogs.d/"
            FileUtils.mkdir_p "#{@base_dir}/tasks/systemtaillogs.d/"
            FileUtils.mkdir_p "#{@base_dir}/tasks/bundlelogs.d/"
            FileUtils.mkdir_p "#{@base_dir}/tasks/publishlogs.d/"
            
            @log_files = {
                :taillogs => Set.new,
                :systemtaillogs => Set.new,
                :bundlelogs => Set.new,
                :publishlogs => Set.new
            }
            
            @log_rotate_hash = {
                :hourly => true,
                :size => '10M',
                :rotate => '10',
                :missingok => true,
                :compress => true,
                :notifempty => true,
                :copytruncate => true,
                :dateext => true,
                :dateformat => '%s'
            }
        end
        
        # Adds a log file to current set of configuration.
        #
        # === Examples
        # 
        #   conf_manager = ElasticBeanstalk::LogConfManager.new('base', base_dir: '/opt/elasticbeanstalk')
        #   conf_manager.add('/var/log/httpd/*') #=> this results in adding '/var/log/httpd/*' to all types of logs
        #   conf_manager.add('/var/log/httpd/*', types: [:all]]) #=> this results in adding '/var/log/httpd/*' to all types of logs
        #   conf_manager.add('/var/log/httpd/*', types: [:taillogs]]) #=> this results in adding '/var/log/httpd/*' to taillogs
        #   conf_manager.add('/var/log/httpd/*', types: [:taillogs, :systemtaillogs]]) #=> this results in adding '/var/log/httpd/*' to both taillogs and systemtaillogs
        #
        # === Attributes
        #
        # * +file_pattern+ Log file pattern to add to the set of given log types.
        # * +types+ (Optional) Array of log types to add the given log file to. Valid log types are :all, :taillogs, :systemtaillogs, :bundlelogs, :publishlogs. Default is to add the file pattern to all types.
        #
        def add(file_pattern, types: [:all])
            types = [:taillogs, :systemtaillogs, :bundlelogs, :publishlogs] if types == [:all]
            types.each do |type|
                raise BeanstalkRuntimeError, %[Invalid log type: #{type}] unless type?(type)
                @log_files[type].add(file_pattern)
            end
        end
        
        def read_log_rotation_settings(settings_file)
            rotation_settings_hash = {}
            rotation_settings_str = File.read(settings_file)
            skip = false
            rotation_settings_str.each_line do |line|
                line.chomp!
                if ['postrotate', 'prerotate', 'firstaction', 'lastaction'].include?(line)
                    skip = true
                end
                if !skip
                    parts = line.split(' ', 2)
                    if parts.size == 1
                        rotation_settings_hash[parts[0].to_sym] = true
                    elsif parts.size == 2
                        rotation_settings_hash[parts[0].to_sym] = parts[1]
                    end
                end
                if 'endscript' == line
                    skip = false
                end
            end
            
            ['postrotate', 'prerotate', 'firstaction', 'lastaction'].each do |key|
                block = script_block(rotation_settings_str, key, 'endscript')
                if !block.empty?
                    rotation_settings_hash[key.to_sym] = block
                end
            end
            
            @log_rotate_hash = rotation_settings_hash
        end

        # Writes the array of file patterns to the log conf files in addition to writing the log rotation options.
        #
        # === Examples
        # 
        # manager = ElasticBeanstalk::LogConfManager.new('base', base_dir: '/opt/elasticbeanstalk')
        # manager.add('/var/log/httpd/*')
        # manager.add('/var/log/messages')
        # manager.log_rotate_hash[:size] = '100M'
        # manager.log_rotate_hash[:compress] = false
        # manager.log_rotate_hash[:create] = true
        # manager.write
        #
        # The write call results in the generation of the following files:
        # /opt/elasticbeanstalk/tasks/taillogs.d/base.conf:
        #     /var/log/httpd/*out
        #     /var/log/httpd/*txt
        #     /var/log/httpd/*log
        #     /var/log/messages
        # /opt/elasticbeanstalk/tasks/systemtaillogs.d/base.conf:
        #     /var/log/httpd/*out
        #     /var/log/httpd/*txt
        #     /var/log/httpd/*log
        #     /var/log/messages
        # /opt/elasticbeanstalk/tasks/bundlelogs.d/base.conf:
        #     /var/log/httpd/*
        #     /var/log/messages
        # /opt/elasticbeanstalk/tasks/publishlogs.d/base.conf:
        #     /var/log/httpd/*.gz
        #     /var/log/messages
        # /opt/elasticbeanstalk/logrotate.elasticbenastalk.base.conf:
        #     /var/log/httpd/* /var/log/messages {
        #        hourly
        #        size 10M
        #        rotate 10
        #        missingok
        #        notifempty
        #        copytruncate
        #        dateext
        #        dateformat %s
        #        create
        #    }
        #
        def write
            if !@log_files[:taillogs].empty?
                File.open("#{@base_dir}/tasks/taillogs.d/#{@conf_file}.conf", 'w') do |f|
                    f.write(tail_logs.to_a.join("\n"))
                end
            end
            
            if !@log_files[:systemtaillogs].empty?
                File.open("#{@base_dir}/tasks/systemtaillogs.d/#{@conf_file}.conf", 'w') do |f|
                    f.write(systemtail_logs.to_a.join("\n"))
                end
            end
            
            if !@log_files[:bundlelogs].empty?
                File.open("#{@base_dir}/tasks/bundlelogs.d/#{@conf_file}.conf", 'w') do |f|
                    f.write(@log_files[:bundlelogs].to_a.join("\n"))
                end
            end

            if !@log_files[:publishlogs].empty?            
                File.open("#{@base_dir}/tasks/publishlogs.d/#{@conf_file}.conf", 'w') do |f|
                    f.write(publish_rotated_logs.join("\n"))
                end
            end
            
            if !@log_files[:publishlogs].empty?
                File.open("#{@logrotateconf_dir}/logrotate.elasticbeanstalk.#{@conf_file}.conf", 'w') do |f|
                    publish_logs.each do |pattern|
                        rotate_hash = @log_rotate_hash
                        rotate_hash[:olddir] = rotated_log_dir(pattern)
                        FileUtils.mkdir_p(rotate_hash[:olddir])
                        f.write("#{pattern} \{\n#{log_rotation_settings(rotate_hash)}\}\n\n")
                    end
                end
                
                if @log_rotate_hash.has_key?(:hourly)
                    File.open("#{@hourly_cron_dir}/cron.logrotate.elasticbeanstalk.#{@conf_file}.conf", 'w') do |f|
                        f.write("#!/bin/sh\n")
                        f.write("test -x /usr/sbin/logrotate || exit 0\n")
                        f.write("/usr/sbin/logrotate -f #{@logrotateconf_dir}/logrotate.elasticbeanstalk.#{@conf_file}.conf\n")
                    end
                    FileUtils.chmod("+x", "#{@hourly_cron_dir}/cron.logrotate.elasticbeanstalk.#{@conf_file}.conf")
                end
            end
        end
        
        private
        
        # Checks whether the given log type is valid or not.
        # Valid log types are :taillogs, :systemtaillogs, :bundlelogs, :publishlogs.
        #
        def type?(type)
            [:taillogs, :systemtaillogs, :bundlelogs, :publishlogs].include?(type)
        end
        
        def tail_logs
            @log_files[:taillogs]
        end

        def systemtail_logs
            @log_files[:systemtaillogs]
        end

        def publish_logs
            @log_files[:publishlogs]
        end

        # We always publish all files from specified rotated directory
        def publish_rotated_logs
            @log_files[:publishlogs].inject([]) do |file_patterns, log_pattern|
                file_patterns << File.join(rotated_log_dir(log_pattern), "*")
            end
        end

        # Format the rotated log directory.
        def rotated_log_dir (pattern)
            log_path = Pathname.new(pattern).dirname
            rotated_log_path = File.join(log_path, @logrotate_subdir)
        end

        def log_rotation_settings(log_rotate_hash)
            log_rotate_hash.inject("") do |log_rotate_str, (key, value)|
                if ['postrotate', 'prerotate', 'firstaction', 'lastaction'].include?(key.to_s)
                    log_rotate_str << value << "\n"
                elsif key.to_s == "hourly"
                    log_rotate_str
                elsif value.is_a?(String)
                    log_rotate_str << key.to_s << " " << value << "\n"
                elsif value == true
                    log_rotate_str << key.to_s << "\n"
                else
                    log_rotate_str
                end
            end
        end
        
        def script_block(str, start_line, end_line)
            block = str.lines.drop_while { |line| line.chomp != start_line }.take_while { |line| line.chomp != end_line }
            block << end_line unless block.empty?
            block.join
        end
    end
end
