$:.unshift File.dirname(__FILE__)

#$oats_unit_test = { 'input_args' => [ "-g" , "#{UNIT_TEST_DIR}/test_xl_lists_Gemfile.rb" ]}
require 'common_test_unit_setup'

class Test_Xl_Lists < Test::Unit::TestCase
  include Oats::CommonTestUnitSetup

  def test_xl_lists
#    params.delete('-q')
    test_lists = Oats.run(['-q', 'SampleXlLists.xls'])['test_files'].variations.first.tests
    assert_equal 2, test_lists[0].variations.first.pass , "Passes in first worksheet doesn't match"
    assert_equal 1, test_lists[1].variations.first.pass , "Passes in secod worksheet doesn't match"
  end

end
