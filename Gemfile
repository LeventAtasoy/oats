source 'http://rubygems.org'

unless defined?(OATS_GEM_IS_ALREADY_INCLUDED)
  OATS_GEM_IS_ALREADY_INCLUDED = true

  gemspec
  # Include Gemfile from dir_tests
  unless ENV['OATS_TESTS']
    ENV['OATS_TESTS'] =  File.expand_path('oats_tests', File.dirname(__FILE__) )
    puts "Undefined OATS_TESTS Environment variable, assuming: " + ENV['OATS_TESTS']
  end
  test_gemfile = $oats_execution['options'][ "_:gemfile"] if $oats_execution and $oats_execution['options']
  test_gemfile ||= ENV['OATS_TESTS'] + '/Gemfile'
  if File.exist?(test_gemfile)
    puts "Including AUT Gemfile: " + test_gemfile
    eval(IO.read(test_gemfile), binding)
  end
  
  
end
