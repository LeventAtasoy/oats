unless defined?(OATS_GEM_IS_ALREADY_INCLUDED)
  # Specify your gem's dependencies in oats.gemspec
  gemspec

  # Include Gemfile from dir_tests
  ENV['OATS_TESTS'] ||=  File.expand_path('oats_tests', File.dirname(__FILE__) )
  puts "Undefined OATS_TESTS Environment variable, assuming: " + ENV['OATS_TESTS']
  gemfile = $oats_execution['options'][ "_:gemfile"] if $oats_execution and $oats_execution['options']
  gemfile ||= ENV['OATS_TESTS'] + '/Gemfile'
  eval('OATS_GEM_IS_ALREADY_INCLUDED = true;' + IO.read(gemfile), binding) if File.exist?(gemfile)
end