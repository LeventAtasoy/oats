source "http://rubygems.org"

# Specify your gem's dependencies in oats.gemspec
gemspec

# Include Gemfile from dir_tests
raise "Undefined OATS_TESTS Environment variable" unless ENV['OATS_TESTS']
gemfile = $oats_execution['options'][ "_:gemfile"] || ENV['OATS_TESTS'] + '/Gemfile'
eval('OATS_GEM_IS_ALREADY_INCLUDED = true;' + IO.read(gemfile), binding) if File.exist?(gemfile)
