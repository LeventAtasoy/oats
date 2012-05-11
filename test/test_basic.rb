$:.unshift File.dirname(__FILE__)
require 'common_test_unit_setup'

class TestBasic < Test::Unit::TestCase
  include Oats::CommonTestUnitSetup

  def test_locate_in_subdir
    assert_equal 1, num_passed('occTest_1.rb'),"Test Failed"
  end

  def test_multiple_tests
    assert_equal 4, num_passed('occTestlist.yml'),"Test Failed"
  end


end
