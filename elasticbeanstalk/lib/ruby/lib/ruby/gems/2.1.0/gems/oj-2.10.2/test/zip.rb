#!/usr/bin/env ruby
# encoding: UTF-8

$: << File.dirname(__FILE__)

require 'helper'

require 'zlib'

File.open('test.json.gz', 'r') do |file|
  Zlib::GzipReader.wrap(file) do |f2|
    puts "*** f2: #{f2}"
    Oj.load(f2) do |val|
      puts val
    end
  end
end

=begin
And a json file with the following contents (then gzipped):

{"a":2}
{"b":2}
The output is:

{"a"=>2}
{"b"=>2}
bin/test:8:in `load': undefined method `new' for #<EOFError: end of file reached> (NoMethodError)
    from bin/test:8:in `block (2 levels) in <main>'
    from bin/test:7:in `wrap'
    from bin/test:7:in `block in <main>'
    from bin/test:6:in `open'
    from bin/test:6:in `<main>'
=end
