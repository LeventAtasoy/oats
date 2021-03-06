require 'oats/report'
require 'oats/test_data'
require 'oats/application_logs'
require 'oats/oats_data'
require 'oats/roptions'
require 'oats/build_id'
require 'oats/email'

module Oats

  module Driver

    def Driver.init(args=nil)
      unless ENV['HOSTNAME']
        if Oats.os == :windows
          ENV['HOSTNAME'] = ENV['COMPUTERNAME']
        else
          ENV['HOSTNAME'] = `hostname`.chomp
        end
      end
      Log4r::Logger.root.level = Log4r::DEBUG
      Log4r::StdoutOutputter.new('console', :level => 1,
                                 :formatter => Log4r::PatternFormatter.new(:depth => 50,
                                                                           :pattern => "%-5l %d %M", :date_pattern => "%y-%m-%d %H:%M:%S"))
      $log = Log4r::Logger.new('R')
      $log.add('console')
      options = CommandlineOptions.options(args)
      $oats_info = {}
      $oats_global = {}
      @@quiet = options['_:quiet'] # save quiet option from initial commandline options
      $log.remove('console') if @@quiet
      ENV['OATS_USER_HOME'] ||= ENV['HOME']
      ENV['OATS_USER_HOME'] = Util.expand_path(ENV['OATS_USER_HOME']) if ENV['OATS_USER_HOME'] # Normalize for cygwin
      options
    end

    # Main method that starts oats execution in either agent or standalone mode.
    # Parameters are command-line arguments
    # Returns oats_info object containing execution results
    def Driver.run(args)
      options = Driver.init(args)
      Driver.start(nil, options)
      $oats_info
    end

    # Executes OATS
    # Returns oats_info object containing execution results
    def Driver.start(jid, options)
      begin
        $oats_info = {} # Holds Oats.context, to be transmitted to OCC
        $oats_global = {} # Holds Oats.global for inter-test data, within an execution sequence
        Oats.context['start_time'] = Time.new.to_i
        if jid
          Oats.global['agent'] = $oats_execution['agent']
          Oats.context['jobid'] = jid
        else
          Oats.context['jobid'] = Oats.context['start_time'].to_s[2..-1]
        end
        return false unless OatsLock.set
        $log.remove('console') if options['_:quiet']
        $oats_execution['oats_init'] and $oats_execution['oats_init'].each_pair do |klas, args|
          klas.init
        end
        Oats.global['test_data'] = {}
        TestList.current = nil # Initialize
        $oats = nil # Holds Oats.data, the resolved oats.yml contents
        oats_data = OatsData.load(options['_:ini_file'])
        $oats = oats_data
        $oats['_']['options'] = options
        Roptions.override(options)
        Oats.result_archive_dir # Adjust results_ dir variables if running on agent mode
        oats_data = $oats
        Selenium.reset if defined?(Selenium) and Selenium.respond_to?(:reset) # Initialize class variables and kill running browsers, in case running in server host mode
        #      oats_data['execution']['test_files'] = test_files if test_files and ! test_files.empty?
        dir_res = oats_data['execution']['dir_results']
        stop_file = dir_res + '/stop_oats'
        oats_data['execution']['stop_file'] = stop_file
        if stop_file and File.exist?(stop_file)
          $oats_info['stop_oats'] = Time.new.to_i
          FileUtils.mv(stop_file, dir_res + '/stop_file_' + Oats.context['jobid'])
        end
        Report.archive_results
        FileUtils.mkdir_p(dir_res)
        oats_data['execution']['log'] = oats_data['execution']['dir_results'] + '/oats.log'
        oats_log = oats_data['execution']['log']
        unless oats_data['execution']['tail_logs_ip']
          if oats_log
            dir_oats_log = File.dirname(oats_log)
            raise(OatsBadInput, "Can not locate directory of execution:log #{dir_oats_log}") unless File.directory?(dir_oats_log)
            oats_log = Util.expand_path(oats_log)
            # Ensure log_level valid
            level = Log4r::Log4rConfig::LogLevels.index($oats['execution']['log_level'])
            raise(OatsBadInput, "Unrecognized execution:log_level [#{$oats['execution']['log_level']}]") unless level
            Log4r::FileOutputter.new('logfile',
                                     :filename => oats_log, :trunc => false, :level => level,
                                     :formatter => Log4r::PatternFormatter.new(:depth => 50,
                                                                               :pattern => "%-5l %d %M", :date_pattern => "%y-%m-%d %H:%M:%S"))
            $log.info "Redirecting output to logfile: " + oats_log
            $log.add('logfile')
          end
          $log.info "Started OATS execution [#{Oats.context['jobid']}] on #{ENV['HOSTNAME']} at #{Time.now}"
        end
        begin
          Oats.info "OATS_TESTS Directory: " + ENV['OATS_TESTS']
          oats_data['_']['environments'] = [] # Keep track of variations stack
          Driver.process_test_yaml(oats_data)
          Report.results($oats_info['test_files'])
          $oats_info['end_time'] = Time.now.to_i
          Report.oats_info_store
          $log.warn "*** Stopping per stop_oats request [#{$oats_info['stop_oats']}]" if $oats_info['stop_oats']
          $log.info "Finished OATS execution [#{Oats.context['jobid']}] at #{Time.at($oats_info['end_time'])} [#{$oats_info['end_time']}]" +
                        (oats_log ? ": " + oats_log : '')
          Report.archive_results(true)
        ensure
          Selenium.reset if defined?(Selenium) and Selenium.respond_to?(:reset)
          message = oats_data['email']
          fail_files = Dir.glob(File.join dir_res, "*-fail.yml")
          if fail_files.empty? && message['pass']
            message = message.merge(message['pass'])
          elsif !fail_files.empty? && message['fail']
            message = message.merge(message['fail'])
          end
          if message['to']
            message['attachments'] ||= [{:type => "text/plain", :name => "oats.log",
                                         :content => Base64.encode64(File.read(oats_log))}]
            unless message[:subject]
              var = $oats_info['test_files'].variations[0]
              list_name = nil
              5.times do
                break if list_name = var.list_name
                var = var.tests[0].variations[0]
              end
              message['subject'] = (fail_files.empty? ? 'Passed' : 'Failed') + (list_name ? ' Test List: ' + list_name : '')
            end
            message['text'] ||= File.read(fail_files[0]) + '\n' unless fail_files.empty?
            Oats::Email.send message
          end
          OatsLock.reset
          $log.add('console') if options['_:quiet'] and !@@quiet
        end
      rescue Exception => e
        $log.debug "Top level Exception caught by test driver."
        $log.error $!
      end
    end

    # Expand additional test_files given as test_yaml.yml plus variations
    def Driver.process_test_yaml(oats_data, id = nil, test_yaml = nil)
      return if $oats_info['stop_oats']
      $oats = oats_data # TestData.locate needs test_dirs location.
      if test_yaml
        oats_data['execution']['test_files'] = nil # Ensure test files exist and taken from the input oats_file
        case test_yaml
          when /\.yml$/
            yaml_file = TestData.locate(test_yaml)
            unless yaml_file
              Oats.error "Can not locate file: #{test_yaml}"
              return
            end
            oats_data = OatsData.load(yaml_file, oats_data)
          #      oats_data['_']['load_history'].last.omit = true
          when /\.xls$/
            suite = id
            require 'spreadsheet' unless defined?(Spreadsheet)
            book = Spreadsheet.open test_yaml, 'rb'
            tests = $oats_global['xl']
            unless tests and tests[id]
              xl_id = File.dirname(id)
              list_id = File.basename(id)
              path = test_yaml.sub(/#{list_id}\.xls$/, File.basename(xl_id)+'.xls')
              Driver.parse_xl(path, xl_id)
              tests = $oats_global['xl']
            end
            header = nil
            book.worksheet('Business Flow').each do |row|
              unless header
                header = row.dup
                next
              end
              test_name = row.shift
              next unless tests[id].include?(test_name)
              test_id = suite + '/' + test_name
              tests[test_id] = {'keywords' => row.collect { |i| i }} # Need to convert to Array
            end

            header = nil
            book.worksheet('Test Data').each do |row|
              unless header
                header = row.dup
                header.shift
                next
              end
              test_name = row.shift
              next unless tests[id].include?(test_name)
              test_id = suite + '/' + test_name
              Oats.assert tests[test_id],
                          "No corresponding TC_ID was defined in Business Flow worksheet for Test Data worksheet TC_ID: " + File.basename(test_id)
              tests[test_id]['data'] = {}
              row.each_with_index do |cell, idx|
                next unless header[idx] and cell
                tests[test_id]['data'][header[idx]] = cell
              end
            end
            list = tests[id].collect { |t| suite + '/' + t + '.xltest' }
            $log.info "Processing worksheet [#{suite}] tests: #{tests[id].inspect}"
            oats_data['execution']['test_files'] = list
        end
      end
      pre = $oats['execution']['handler_pre_test_list']
      if test_yaml and pre
        pre_tst = TestCase.new(pre)
        pre_tst.type = 4
        pre_tst.run
        TestList.current.pre_test = pre_tst
        TestList.current.variations.last.tests.pop
        $log.error pre_tst.errors.first[1] unless pre_tst.errors.empty?
      end
      variations = oats_data['execution']['environments']
      Oats.assert variations, "Missing entry for Oats.data execution.environments"
      # Don't let environment variations propogate down OatsData.history.inspect variations.inspect
      variations = nil if OatsData.history.find { |var| var =~ /\/environments\/#{variations.first}/ }
      # Should also eliminate propogations of other variations if want to support other variations.
      cur_list = TestList.current
      cur_list.variations.last.end_time = Time.now.to_i if cur_list and cur_list.variations.last.end_time.nil?
      new_list = TestList.new(id, test_yaml)
      if variations.nil? or variations.empty?

        Driver.process_oats_data(oats_data)
        new_list.variations.last.end_time = Time.now.to_i
      else
        # Don't let variations files modify test file
        test_files = oats_data['execution']['test_files']
        #      # Don't let current variations propagate down
        variations.each do |variation|
          begin
            new_list.add_variation(variation)
            break if $oats_info['stop_oats']
            variation = variation.sub(/\.yml$/, '') # Get rid of extension, if provided.
            $oats_info['environment_name'] = variation if variation
            # Look for variation in environments
            environment_variation = Util.expand_path(variation+'.yml',
                                                     File.join(oats_data['execution']['dir_tests'], 'environments'))
            raise(OatsError, "Can not locate variation [#{variation}]: #{environment_variation}") \
              unless File.exist?(environment_variation)
            new_oats_data = OatsData.load(environment_variation, oats_data)
            new_oats_data['env']['name'] = variation
            new_oats_data['_']['load_history'].last.in_result_dir = false if variations.length == 1
            new_oats_data['_']['environments'] << variation
            # If the same variation is found in user's directories, merge it
            user_var_dir = oats_data['execution']['dir_environments']
            if user_var_dir and File.directory?(user_var_dir)
              users_variation = Util.expand_path(variation+'.yml', user_var_dir)
              if File.exist?(users_variation) and # in case input was absolute
                  not File.identical?(users_variation, environment_variation)
                new_oats_data = OatsData.load(users_variation, new_oats_data)
                new_oats_data['_']['load_history'].last.in_result_dir = false if variations.length == 1
                new_oats_data['_']['environments'] << users_variation
                # Keep only one name, the one in the user's variation in history
                #              new_oats_data['_']['load_history'][-2].omit = true
              end
            end
            new_oats_data['execution']['test_files'] = test_files
            Roptions.overlay($oats['_']['options']) if $oats['_']['options']
            Driver.process_oats_data(new_oats_data)
          rescue OatsError
            $log.error $!.to_s
            $log.error "Test variation is being skipped: #{variation} "
            next
          rescue
            $log.error TestCase.backtrace($!)
            $log.error "Test variation is being skipped: #{variation} "
            next
          ensure
            new_list.variations.last.end_time = Time.now.to_i
          end
        end
      end
      new_list.end_time = Time.now.to_i
      new_list.variations.last.end_time = new_list.end_time unless new_list.variations.last.end_time
      TestList.current = cur_list if cur_list
    end

    # Process each test_file in oats_data once
    def Driver.process_oats_data(oats_data)
      stop_file = oats_data['execution']['stop_file']
      $oats = oats_data # Oats Data becomes global only this point down to allow recursion.
      # begin
      #   ApplicationLogs.tail_errors # If the user just wants to tail, this never returns
      # rescue OatsBadInput
      #   $log.fatal $!.to_s
      #   exit
      # end
      # The environment file for tailing is included only in the user's very first variation.
      test_files = oats_data['execution']['test_files']
      if !test_files or test_files.empty?
        $log.fatal("Must provide at least one test.")
        $log.fatal 'Effective config file sequence ' + OatsData.history[1..-1].inspect
        return
      end
      BuildId.generate # Specific to the AUT, supplied in the test_dir/lib
      # Dump oats_data and start each test with a fresh copy each time to avoid contamination
      oats_data_dump = Marshal.dump(oats_data)
      while test_file = test_files.shift do
        skip_test = false
        if stop_file and File.exist?(stop_file)
          $oats_info['stop_oats'] = Time.new.to_i
          FileUtils.mv(stop_file, stop_file + '_' + $oats_info['start_time'].to_s[2..-1])
        end
        break if $oats_info['stop_oats']
        $oats = Marshal.load(oats_data_dump)
        begin
          if test_file.instance_of? Array
            tst = TestCase.new(test_file)
            tst.run
          else
            id, extension, path, handler = TestCase.parse_test_files(test_file)
            restrict_tests = $oats['execution']['restrict_tests']
            if restrict_tests and restrict_tests.include?(test_file)
              $oats['execution']['no_run'] = 'restrict_tests'
              #            skip_test = true
              #            next
            end
            if (extension == 'yml' and handler.nil?) or extension == 'xlw'
              unless path
                $log.error "Could not locate test list '#{id}'"
                TestList.current.variations.last.tests.pop
                return
              end
              begin
                Driver.process_test_yaml($oats, id, path)
              ensure
                post = $oats['execution']['handler_post_test_list']
                $oats = Marshal.load(oats_data_dump)
                if post
                  post_tst = TestCase.new(post)
                  post_tst.type = 0
                  post_tst.run
                  TestList.current.post_test = post_tst
                  TestList.current.variations.last.tests.pop
                  $log.error post_tst.errors.first[1] unless post_tst.errors.empty?
                end
              end
            else
              case extension
                when 'xls'
                  # Use it to include for suite.worksheet entries into test_files.
                  # Later process these similar to list.yml files
                  unless path
                    $log.error "Could not locate XL file '#{id}'"
                    TestList.current.variations.last.tests.pop
                    return
                  end
                  test_files.concat Driver.parse_xl(path, id)

                when 'txt'
                  list = TestList.txt_tests(path)
                  $log.info "Including test list [#{path}]: #{list.inspect}"
                  test_files = list + test_files
                  skip_test = true

                else
                  tst = TestCase.new(test_file, id, extension, path, handler)
                  tst.run
              end
            end
          end
            #      rescue OatsError  # OatsTestError # Explicit Test Failure Assertion
            #        $log.debug "OatsError exception caught by test driver"
            #        tst = TestCase.new(test_file,path) unless path # TestData.Locate has failed
            #        $log.error $!.to_s.chomp
            #        TestData.error($!)
        rescue Exception => e
          $log.debug "General Exception caught by test driver."
          case e
            when OatsVerifyError # Selenium::CommandError, Timeout::Error then $log.error backtrace($!)
              $log.error e.to_s.chomp
            when OatsError
              $log.error TestCase.backtrace(e)
            else
              $log.error e
          end
          tst = TestCase.new(test_file) unless tst # just in case something happened above before test creation
          TestData.error(e)
          Oats.system_capture
        ensure
          if $oats_global['test_files'].instance_of?(Array)
            test_files += $oats_global['test_files']
            $oats_global.delete 'test_files'
          end
          next if skip_test or tst.nil? or tst.instance_of?(TestList) # coming from next above
          tst.end_time = Time.new.to_i
          case tst.status
            when 0 then
              $log.info "PASSED: #{tst.id}"
            when 1 then
              $log.warn "FAILED: #{tst.id} [#{tst.errors.last[1].chomp}]"
            when 2 then
              $log.warn "SKIPPED: #{tst.id}"
            else
              if tst.status.nil? and $oats_execution['agent']
                $log.error "Removing results of last test due to empty test.status, possibly due to agent shutdown."
                TestData.tests.pop
              else
                $log.error "Unrecognized test.status: [#{tst.status}] for [#{tst.name}] . Please inform OATS administrator."
              end
          end
          test_outputter = Log4r::Outputter['test_log']
          if test_outputter and !test_outputter.closed?
            test_outputter.close
            $log.remove('test_log')
          end
          Report.oats_info_store
        end
      end

    end

    # Return all the included worksheet lists in XL and place all
    # their test arrays in $oats_global['xl']
    def Driver.parse_xl(path, id)
      require 'spreadsheet' unless defined?(Spreadsheet)
      book = Spreadsheet.open path, 'rb'
      sheet = book.worksheet 'Main'
      Oats.assert sheet, "Could not locate worksheet 'Main' in: " + path
      list = Driver.xl_sheet_tests(sheet, id, 'Main', 'Test_Scenarios')
      Oats.assert !list.empty?, "No executable worksheets are listed in Main worksheet in: " + path
      $log.info "Processing 'Main' worksheet in XL file: " + path
      $log.info "Worksheets to be included: #{list.inspect}"
      tests = $oats_global['xl'] = {}
      test_files = []
      list.each do |ws|
        sheet = book.worksheet ws
        Oats.assert sheet, "XL file does not contain worksheet: " + ws
        suite_ws = id + '/' + ws
        execute_index = test_index = nil
        tests[suite_ws] = Driver.xl_sheet_tests(sheet, id, ws, 'Test_Cases')
        Oats.assert !tests[suite_ws].empty?, "No executable tests are listed in worksheet: " + suite_ws
        test_files.push suite_ws + '.xlw'
      end
      test_files
    end

    def Driver.xl_sheet_tests(sheet, xl, ws, test_header)
      execute_index = test_index = nil
      msg = " in worksheet '#{ws}' of: #{xl}"
      sheet.collect do |row|
        if test_index
          #          Oats.assert row[test_index], "Missing value in column '#{test_header}'" + msg
          row[test_index] if row[execute_index] and (row[execute_index] == true or row[execute_index].downcase == 'true')
        else
          row.each_with_index do |col, idx|
            case col
              when test_header then
                test_index = idx
              when 'Execute' then
                execute_index = idx
            end
          end
          Oats.assert test_index, "Missing column '#{test_header}' "+ msg
          Oats.assert test_index, "Missing column 'Execute' "+ msg
        end
      end.compact
    end

  end
end