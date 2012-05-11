$:.unshift File.dirname(__FILE__)
#$oats_unit_test = { 'input_args' => [ "-g" , "#{UNIT_TEST_DIR}/test_selenium_Gemfile.rb" ]}
require 'common_test_unit_setup'

class TestSelenium < Test::Unit::TestCase
  include Oats::CommonTestUnitSetup

  def test_selenium
    assert_equal 1, num_passed('seleniumGoogle.rb'),"Test Failed"
  end

  def test_webdriver
    assert_equal 1, num_passed('webdriverGoogle.rb'),"Test Failed"
  end

end
