$:.unshift File.join(File.dirname(__FILE__),'..','lib')

require 'test/unit'
require 'oats'

module Oats
  module CommonTestUnitSetup

    DEFAULT_PARAMS =  ['-q']

    # To get the full logs from tests, set params to nil
    def num_passed(test, params = DEFAULT_PARAMS.dup)
      params.push(test)
      test_files = Oats.run(params)['test_files']
      if test_files
        tlh = test_files.testlist_hash
        tlh['pass'] if tlh
      end
    end
  end
end
