
defined? Jruby && JRuby.objectspace = true # avoid error  http://rubyforge.org/pipermail/nokogiri-talk/2010-April/000355.html

$oats_execution = {}  # Keeps variables that persists throughout a agents life, across testlists
# Need to be before reading classes to allow the loaded classes register themselves here
# In agent mode, this will contain 'options'.
# Classes of OATS can check existence of this to determine whether called by OATS or OCC

require 'pp'
require 'oats/commandline_options'
options = Oats::CommandlineOptions.options
$oats_execution['options'] = options
if options['execution:occ:agent_nickname'] || options['execution:occ:agent_port'] || options['_:command']
  $oats_execution['agent'] = options  # Existence of this from now on implies running in agent mode
end

ENV['OATS_HOME'] ||= File.expand_path( '..', File.dirname(__FILE__) )
ENV['OATS_TESTS'] ||= options['_:dir_tests'] || (ENV['OATS_HOME'] + '/oats_tests')

$:.unshift(ENV['OATS_TESTS'] + '/lib')

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