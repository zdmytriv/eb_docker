# -*- encoding: utf-8 -*-
# stub: beanstalk-core 1.0 ruby lib

Gem::Specification.new do |s|
  s.name = "beanstalk-core"
  s.version = "1.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.authors = ["Amazon Web Services Elastic Beanstalk"]
  s.date = "2014-09-23"
  s.description = "Common utilities for AWS Elastic Beanstalk on-instance use"
  s.email = "nospam@amazon.com"
  s.executables = ["log-conf", "get-config", "command-processor"]
  s.files = ["bin/command-processor", "bin/get-config", "bin/log-conf"]
  s.homepage = "https://aws.amazon.com/elasticbeanstalk/"
  s.licenses = ["Amazon Software License"]
  s.required_ruby_version = Gem::Requirement.new(">= 2.1")
  s.rubygems_version = "2.2.2"
  s.summary = "AWS EB core utilities"

  s.installed_by_version = "2.2.2" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<executor>, ["~> 1.0"])
    else
      s.add_dependency(%q<executor>, ["~> 1.0"])
    end
  else
    s.add_dependency(%q<executor>, ["~> 1.0"])
  end
end
