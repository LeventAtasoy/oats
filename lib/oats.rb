
defined? Jruby && JRuby.objectspace = true # avoid error  http://rubyforge.org/pipermail/nokogiri-talk/2010-April/000355.html

$oats_execution = {}  # Keeps variables that persists throughout a agents life, across testlists
# Need to be before reading classes to allow the loaded classes register themselves here
# In agent mode, this will contain 'options'.
# Classes of OATS can check existence of this to determine whether called by OATS or OCC

require 'pp'


# Add oats/lib into the path
ENV['OATS_TESTS'] = ENV['OATS_TESTS'].gsub('\\','/') if ENV['OATS_TESTS']
ENV['OATS_HOME'] = ENV['OATS_HOME'] ? ENV['OATS_HOME'].gsub('\\','/') : File.expand_path( '..', File.dirname(__FILE__) )
oats_lib = File.join(ENV['OATS_HOME'] , 'lib')
$:.unshift(oats_lib) unless $:.include?(oats_lib)

require 'oats/commandline_options'
options = Oats::CommandlineOptions.options
$oats_execution['options'] = options
if options['execution:occ:agent_nickname'] || options['execution:occ:agent_port'] || options['_:command']
  $oats_execution['agent'] = options  # Existence of this from now on implies running in agent mode
end

# Add oats_tests/lib into the path
ENV['OATS_TESTS'] ||= options['_:dir_tests'] ||  File.expand_path('../oats_tests', ENV['OATS_HOME'])
oats_test_lib = File.join(ENV['OATS_TESTS'] , 'lib')
$:.unshift(oats_test_lib) unless $:.include?(oats_test_lib)

ENV['OATS_USER_HOME'] = ENV['OATS_USER_HOME'].gsub('\\','/') if ENV['OATS_USER_HOME']

require 'oats/keywords'

# GEMS needed by OATS.
require 'rubygems'
#require "bundler/setup"
#Bundler.require
#require 'deep_merge' # Need modified version of https://github.com/danielsdeleo/deep_merge for 1.9 compatibility
require 'log4r'  # http://log4r.sourceforge.net/rdoc/index.html

require 'oats/driver'
require 'oats/oats_lock'

require 'oats/user_api' #  Interface methods to user methods implemented in other modules

Dir.foreach(oats_test_lib) do |file|
  if File.extname(file) == '.rb'
    require file
  end
end
