#!/usr/bin/env ruby
ENV['OATS_TESTS'] ||= File.expand_path(File.dirname(File.dirname(__FILE__)))
oats_lib = File.expand_path('../oats/lib', ENV['OATS_TESTS'])
if File.directory?(oats_lib) and false
  $:.unshift(oats_lib)
else
  require 'rubygems' unless defined? Gem
  gem 'oats'
end
require 'oats'
Oats.run
