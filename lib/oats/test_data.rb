require 'oats/test_list'
require 'oats/test_case'

module Oats

  # Interface module for TestCase or TestList related operations
  module TestData
    @@pause_after_error = false

    # Returns array of test objects in the currently executing list
    # TestData.tests[-1] is the same as as the current_test
    def TestData.tests
      cur_test_list = TestList.current
      return nil unless cur_test_list
      vars = cur_test_list.variations
      return nil unless vars
      last_var = vars.last
      return nil unless last_var
      tests = last_var.tests
      return nil unless tests
      return tests
    end

    # Returns last test in the currently executing list
    # index:: of the test in tests array. Default is last
    def TestData.current_test
      TestData.tests[-1]
    end

    def TestData.previous_test
      TestData.tests[-2]
    end

    def TestData.pause_after_error
      @@pause_after_error
    end

    def TestData.pause_after_error=(do_pause)
      @@pause_after_error = do_pause
    end

    def TestData.error(exception)
      raise exception unless TestData.current_test
      error = [exception.class.to_s,exception.message, exception.backtrace]
      TestData.current_test.errors << error
      TestData.current_test.status = 1
      @@pause_after_error = true
    end

    # Returns absolute path after locating file in test directories, or nil
    # If exact match is not found, searches with added .rb extension
    # If dir is false, do not return a directory #
    def TestData.locate(test_file, is_dir = false)
      option ||= {}
      # Don't rely on $oats when called from OCC
      dir_tests = if $oats and $oats['execution'] and $oats['execution']['dir_tests']
        $oats['execution']['dir_tests']
      else
        ENV['OATS_TESTS']
      end
      Oats.assert test_file, "Test File must be non-nil"
      extn = File.extname(test_file)
      extn = nil if extn == ''
      found_file = catch :found_file do
        if  Oats.os == :windows ? test_file[1] == ?: : test_file[0] == ?/ # absolute path
          # Try exact match
          throw(:found_file, test_file) if File.exist?(test_file) and (is_dir or not FileTest.directory?(test_file))

          # Try globbing the input name as is

          found_file = File.exist?(test_file)
          throw(:found_file, test_file ) if found_file and (is_dir or not FileTest.directory?(test_file))
          throw(:found_file, test_file+'.rb') if File.exist?(test_file+'.rb') unless extn
        end

        # Relative path

        dir_tests = "{#{is_dir},#{dir_tests}}" if is_dir.instance_of?(String) and is_dir != dir_tests

        # 19.2 glob skips over the exact test paths, so try that first
        file = File.join(dir_tests, test_file)
        file += '{,.rb}' unless extn
        found_file = Dir.glob(file).first
        throw(:found_file, found_file) if found_file and (is_dir or not FileTest.directory?(found_file))


        # Try finding it anywhere inside the dir_test tree
        file = File.join(dir_tests, '**', test_file)
        file += '{,.rb}' unless extn
        found_file = Dir.glob(file).first
        throw(:found_file, found_file) if found_file and (is_dir or not FileTest.directory?(found_file))
        return nil
      end
      Oats::Util.expand_path(found_file)
    end

  end
end
