module Oats

  # TestList has array of variations
  class TestList
    # Path of test relative to the dir_tests library
    attr_reader :id
    # Absolute path to the test.yml
    attr_reader :path
    # Array of Variation structures
    attr_accessor :variations
    # Parent variation, start and end times
    attr_accessor :parent_variation, :start_time, :end_time, :pre_test, :post_test
    @@current = nil
    # Currently active test list
    def TestList.current
      @@current
    end
    def TestList.current=(list)
      @@current = list
    end

    def TestList.txt_tests(pth)
      list = IO.readlines(pth)
      list = list.collect{|x| f=x.chomp.sub(/#.*/,'').strip}
      return list.delete_if { |x| x == '' }
    end

    def add_variation(var)
      lv = self.variations.last
      lv.end_time = Time.now.to_i if lv and ! lv.end_time
      if variations.empty? or variations.last.name != 'default'
        variations << Variation.new(var,self)
      else
        variations.last.name = var
        variations.last.start_time = Time.now.to_i
      end
    end

    def testlist_hash
      variation = nil
      top_level_variations = self.variations[0]
      unless top_level_variations.nil? or top_level_variations.tests.nil?
        cur_test_list = top_level_variations.tests[0]
        if cur_test_list
          if cur_test_list.instance_of?(TestCase)
            variation = top_level_variations
          else
            variation = cur_test_list.variations[0]
          end
          # Oats seems to set the end_time of variations incorrectly as equal to
          # start time until very end. Compensate for it by borrowing the time from the TestList
          variation.end_time = cur_test_list.end_time
        end
      end
      return nil unless variation
      return variation.variation_hash(pre_test, post_test)
    end

    def initialize(id, path)
      @id = id
      @path = path
      @start_time = Time.now.to_i
      @variations = []
      add_variation('default')
      $log.info "**** TEST LIST [#{@id}]" if id
      #      raise OatsError, "Encountered recursive inclusion of test lists: [#{tree_id}]"
      if @@current # Make this list a child of current list
        @parent_variation = @@current.variations.last
        @parent_variation.tests << self
      else # record the root
        $oats_info['test_files'] = self
      end
      @@current = self  # Repoint the current list
    end
  end

  # TestList has an array of these
  class  Variation
    attr_reader :tests
    attr_accessor :start_time, :env_name, :name, :list_name, :end_time,  :total, :pass, :fail, :skip, :parent
    def initialize(var,list)
      @parent = list
      @name = var
      @env_name = $oats_info['environment_name'] if $oats_info['environment_name']
      @tests = []
      @start_time = Time.now.to_i
    end


    def variation_hash(pre_test, post_test)
      err_msg = nil
      testlist = self
      $log ||= Rails.logger
      testlist.tests.each_with_index do |tst,idx|
        unless tst.instance_of?(TestCase)
          msg = "Expected a test case in #{testlist.list_name} but got:"
          $log.error "#{msg} #{tst.inspect}"
          msg = "... in job:"
          $log.error "#{msg} #{self.inspect}"
          msg = "Deleting the TestList #{tst.id}"
          err_msg = "Deleted unexpected sub-TestList: #{tst.id}"
          $log.error msg
          testlist.tests.delete(tst)
          next
        end
      end
      testlist.parent = nil

      thash = {
        'fail' => testlist.fail,
        'pass' => testlist.pass,
        'skip' => testlist.skip,
        'total' => testlist.total,
        'start_time' => testlist.start_time,
        'end_time' => testlist.end_time,
        'env_name' => testlist.env_name,
        'list_name' => testlist.list_name,
        'tests' => []
      }
      if pre_test and ! pre_test.errors.empty?
        thash['tests'].push(pre_test)
        thash['fail'] = thash['fail'] ? (thash['fail'] +1) : 1
      end
      if post_test and ! post_test.errors.empty?
        thash['tests'].push(post_test)
        thash['fail'] = thash['fail'] ? (thash['fail'] +1) : 1
      end
      thash['results_error'] = err_msg if err_msg
      testlist.tests.each do |t|
        tc = { 'id' => t.id,
          'status' => t.status,
          'error_capture_file' => t.error_capture_file,
          'result' => t.result,
          'timed_out' => t.timed_out?,
          'start_time' => t.start_time,
          'end_time' => t.end_time      }
        tc['errors'] = t.errors if t.errors
        thash['tests'].push tc
      end
      return thash
    end

  end
end
