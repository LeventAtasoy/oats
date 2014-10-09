# Encapsulates data and methods for each test
require 'oats/mysql.rb'
module Oats

  class TestCase
    # Absolute path of the test
    attr_reader :path
    # extension of the test if it is a single rb file instead of a directory
    attr_reader :is_file
    # Path of handler defined by Oats.data <<:is_file>_extension>_handler
    attr_reader :handler
    # Path of test relative to the dir_tests library
    attr_reader :id
    # Type of last executed rtest file 1:rb, 2:ide, 3:sql, 0: post, 4: pre
    attr_accessor :type
    # Output result directory
    attr_reader :result
    # List of exceptions encountered on the test so far
    attr_reader :errors
    # Current status of the test 0:pass, 1:fail, 2:skip
    attr_accessor :status
    # Time object referring to the end time of the test.
    attr_accessor :end_time
    # Time object referring to the start time of the test.
    attr_reader :start_time
    # Array containing names of the downloded files during the test
    attr_reader :downloaded_files
    # System capture sets this to the name of last error file if one is created
    attr_accessor :error_capture_file

    def initialize(test_file, *args)
      # Do minimal work here to avoid exception. Raise in run, so that test header appears.
      if test_file.instance_of?(Array)
        @method = test_file.shift
        @id = test_file.shift || @method
        @args = test_file
        @path = @id
        @is_file = false
      else
        @id, @is_file, @path, @handler = args.empty? ? TestCase.parse_test_files(test_file) : args
      end
      TestList.current.variations.last.tests << self
      @result = nil
      @status = nil
      @errors = []
      @sql_input_error = nil
      @downloaded_files = []
      @start_time = Time.now.to_i
    end

    def TestCase.parse_test_files(test_file)
      extension = File.extname(test_file)[1..-1]
      handler = $oats['execution'][extension+'_handler'] if extension
      if handler
        handler_located = TestData.locate(handler)
        Oats.assert handler_located, "Could not find handler file #{handler}"
        handler = handler_located
      end
      if extension == 'xlw'
        id = test_file.sub(/\.#{extension}\z/, '')
        test_file = File.join(File.dirname(File.dirname(test_file)), File.basename(test_file, extension) + 'xls')
      end
      path = TestData.locate(test_file, true)
      unless path
        unless handler
          path = File.join($oats['execution']['dir_tests'], test_file)
          if 'xltest' == extension
            test_file.sub!(/\.#{extension}\z/, '')
          else
            path = nil
          end
          return test_file, extension, path, handler
        end
        test_dir = File.dirname(test_file)
        if test_dir == '.'
          path = File.join(File.dirname(handler), File.basename(test_file))
        else
          test_dir = TestData.locate(test_dir, true)
          return test_file, extension, path, handler unless test_dir
          path = File.join(test_dir, File.basename(test_file))
        end
        remove_extension = true
      end
      extension ||= File.extname(path)[1..-1] # In case of implied extensions
      unless id
        id = path.sub(Regexp.new('^' + $oats['execution']['dir_tests'] + '/', Regexp::IGNORECASE), '')
        id.sub!(/\.#{extension}\z/, '') unless remove_extension
      end
      return id, extension, path, handler
    end

    def backtrace(exception=nil)
      TestCase.backtrace(exception)
    end

    def TestCase.backtrace(exception=nil)
      exception ||= $!
      return unless exception.kind_of? Exception
      filtered = exception.backtrace
      if filter = Oats.data('execution.filter_stacktrace')
        filtered.select! { |line| line =~ /[\/|\\]#{filter}[\/|\\]/ }
      end
      return "Caught #{exception.class}: #{exception.message}" + (filtered.empty? ? '' : "\n\t") + filtered.join("\n\t")
    end

    def run
      if @type == 0 or @type == 4

        $log.info "*** #{@type == 0 ? 'POST' : 'PRE'} TEST LIST HANDLER [#{@id}] at #{Time.at(@start_time)}"
      else
        $log.info "*** TEST [#{@id}] at #{Time.at(@start_time)}"
      end
      unless @path
        TestData.error Exception.new("Found no #{@id} file"+
                                         ((@is_file and !%w(rb sql html).include?(@is_file)) ? " nor handler for #{@is_file.inspect}." : ".")
                       )
        return
      end
      if @is_file
        if !%w(rb sql html xltest).include?(@is_file) and !@handler and !@method
          TestData.error Exception.new("Unrecognized extension #{@is_file} for test file [#{@path}]")
          return
        end
      elsif !@method
        unless FileTest.directory?(@path)
          TestData.error Exception.new("Test file must have extension")
          return
        end
      end
      if @is_file
        oats_file = @path.sub(/\.#{@is_file}\z/, '.yml')
        yaml_dir = File.dirname(@path) unless File.exist?(oats_file)
      elsif !@method
        test_var_dir = File.join(@path, 'environments')
        oats_files = Dir.glob(File.join(@path, '*.yml'))
        if oats_files.size == 1
          oats_file = oats_files.first
        else
          yaml_dir = @path
        end
      end
      if yaml_dir
        oats_file = File.join(yaml_dir, 'oats.yml')
        oats_file = nil unless File.exist?(oats_file)
      end
      odat = nil
      if @is_file == 'xltest'
        pth = @id.split('/')
        pth.pop
        suit = pth.pop
        $oats_global['xl'][@id]['data']['keywords'] = $oats_global['xl'][@id]['keywords']
        odat = {pth.pop => {'list' => suit, suit => $oats_global['xl'][@id]['data']}}
      end
      $oats = OatsData.overlay(odat) if odat
      $oats = OatsData.overlay(oats_file) if oats_file
      if test_var_dir and File.directory?(test_var_dir)
        vars_overlayed = []
        $oats['_']['environments'].each do |var_file|
          ## Overlay all previously introduced variations, but only once
          var_name = File.basename(var_file, '.*')
          test_var = File.join(test_var_dir, var_name+'.yml')
          if File.exist?(test_var) and not vars_overlayed.include?(var_name)
            $oats = OatsData.overlay(test_var)
            vars_overlayed << var_name
          end
        end
      end

      conf_hist = OatsData.history[1..-1].collect { |i| i.sub(/#{Oats.data['execution']['dir_tests']}.|#{ENV['OATS_USER_HOME']}./, '') }
      $log.debug 'Effective config file history: ' + conf_hist.inspect

      if $oats['execution']['dir_results']
        FileUtils.mkdir_p($oats['execution']['dir_results']) unless File.directory?($oats['execution']['dir_results'])
        result_root = Util.expand_path(id, $oats['execution']['dir_results'])
      else
        result_root = File.join(@is_file ? File.dirname(@path) : @path, 'result')
      end
      hist_path = OatsData.history(true)
      if hist_path.empty?
        result_dir = result_root
      else
        result_dir = File.join(result_root,
                               hist_path[1..-1].collect { |f| File.basename(f, '.*') }.join('/'))
      end
      if $oats['execution']['no_run'] # Reuse the last timestamped result_dir
        if File.directory?(result_dir)
          latest = Dir.entries(result_dir).last
          result_dir = File.join(result_dir, latest)
        else
          result_dir_save = result_dir
          result_dir = nil
        end
      else
        #      result_dir = File.join(result_dir, @start_time.to_s[2..-1] ) # Create a new timestamped sub result_dir
        FileUtils.mkdir_p(result_dir)
      end
      @result = result_dir
      if result_dir
        test_log = File.join(result_dir, 'oats_test.log')
        Log4r::FileOutputter.new('test_log',
                                 :filename => test_log, :trunc => false, # :level=>level + 1)
                                 :formatter => Log4r::PatternFormatter.new(:depth => 50,
                                                                           :pattern => "%-5l %d %M", :date_pattern => "%y-%m-%d %H:%M:%S"))
        $log.add('test_log')
      end
      if $oats['execution']['no_run']
        @status = 2
        msg = $oats['execution']['no_run'].instance_of?(String) ? (' to '+$oats['execution']['no_run'].inspect) : ''
        $log.warn "Skipping execution since execution:no_run is set#{msg}."
        return
      end
      # Clean download directory
      # Oats::Selenium.mark_downloaded if defined?(Oats::Selenium) and Oats::Selenium.respond_to?(:mark_downloaded)
      # Initialize classes this test may need
      #    $ide = Ide.new unless ENV['JRUBY_BASE']
      # Execute the test
      # ApplicationLogs.new_errors(true) # Reset pre-existing errors
      if @is_file
        oats_tsts = [@handler || @path]
      elsif @method
        oats_tsts = [@method]
      else
        oats_tsts = Dir[File.join(@path, 'rtest*.{rb,html,sql}')].delete_if { |e| /\.gen\./ =~ e }
        oats_tsts.unshift(root + '.html') if File.exist?(@path + '.html') # Compatibility with older tests
        oats_tsts = Dir[File.join(@path, '*.{rb,html,sql}')] if oats_tsts.empty?
        raise(OatsError, "No files matching rtest*.{rb,html,sql} found in: #{@path}") if oats_tsts.empty?
      end
      if result_dir and Oats.data['execution']['run_in_dir_results']
        unless @is_file
          Dir.glob(File.join(@path, '*')).each do |file|
            FileUtils.cp(file, result_dir) if File.file?(file)
          end
        end
        run_dir = result_dir
      else
        raise(OatsError, "Can not run single rb file test without a result_dir.") if @is_file
        run_dir = @path
      end
      quit_on_error = $oats['execution']['quit_on_error']
      skip_unless_previous_test_is_ok = $oats['execution']['skip_unless_previous_test_is_ok']
      Oats.global['rbtests'] = []
      Dir.chdir(run_dir) do
        begin
          oats_tsts.sort!
          oload_hooks(oats_tsts, 'pre', 'unshift')
          oload_hooks(oats_tsts, 'post', 'push')
          #        FileUtils.mkdir_p(out)
          exception_in_rb = false
          oats_tsts.each do |rt|
            break if quit_on_error and not errors.empty?
            if skip_unless_previous_test_is_ok and TestData.previous_test and TestData.previous_test.status != 0
              $oats['execution']['no_run'] = true
              Oats.info "Skipping due to previous test failure"
            end
            raise(OatsError, "Can not read file [#{rt}]") unless File.readable?(rt) unless @method or @is_file == 'xltest'
            begin
              case @is_file
                when 'html'
                  Oats.ide(rt)
                when 'sql'
                  Oats.mysql(rt)
                else
                  begin

                    if @method
                      $log.info "Executing OatsTest:#{@method}"
                      Oats.global['rbtests'] << rt # Not sure if this is needed
                      Oats.global['oloads'] = [] # Not sure if this is needed
                      exception_in_rb = true
                      method_name = File.extname(@method)
                      class_name = File.basename(@method,method_name)
                      Kernel.const_get(class_name).send(method_name[1..-1],*@args)
                      exception_in_rb = false
                    else
                      if @is_file =~ /^rb$||^xltest$/

                        next if exception_in_rb # Don't process a second rb if one throws an exception
                        Oats.global['rbtests'] << rt
                        Oats.global['oloads'] = []
                        exception_in_rb = true
                        if @is_file == 'xltest'
                          $log.info "Processing test: #{rt}"
                          Oats::Keywords.process
                        else
                          $log.info "Processing rb file: #{rt}"
                          load(rt, true)
                        end
                        exception_in_rb = false
                      else # if else
                        raise OatsError, "Unrecognized test extension #{@is_file}"
                      end
                    end

                  rescue OatsTestExit # Regular exit from the rb test
                    message = $!.message
                    $log.info message unless message == 'OatsTestExit'
                  rescue Exception => e
                    case e
                      when OatsError, Timeout::Error then
                        $log.error backtrace($!)
                      else
                        $log.error $! # Full stackstrace
                    end
                    TestData.error($!)
                    if defined?(Oats::Selenium) and Oats::Selenium.respond_to?(:system_capture) and
                        ! Oats.data['selenium']['skip_capture']
                      Selenium.system_capture
                    end
                  ensure
                    Selenium.pause_browser if defined?(Oats::Selenium) and Oats::Selenium.respond_to?(:pause_browser)
                  end
              end # case else
            rescue OatsMysqlNoConnect # at 6 deep
              @sql_input_error = true
              @status = 2
              $log.warn "#{$!}. Test is classified as SKIPPED."
            rescue OatsError # No stack for known errors from rmsql and ide
              $log.error $!.to_s
              TestData.error($!)
            rescue # Otherwise want the stack trace
              $log.error TestCase.backtrace($!)
            end
          end
        ensure
          begin
            $mysql.processlist if timed_out? # Ensure selenium closes if this throws an exception
          rescue
          end
          Selenium.reset if defined?(Selenium) and Selenium.respond_to?(:reset) and
              ($oats['selenium']['keep_alive'].nil? or !errors.empty?)
          FileUtils.rm_rf(out) if File.directory?(out) and
              Dir.glob(File.join(out, '*')).empty?
          if $oats['execution']['no_run']
            $log.warn "Classifying test as SKIPPED since execution:no_run is set"
            @status = 2
            return
          end
        end
      end

      # of the out generation phase

      # Verify phase
      if result_dir
        verify
      else
        $log.warn "Skipping verification, can not find result directory: #{result_dir_save}"
      end
      # log_errors = ApplicationLogs.new_errors
      # unless log_errors.empty?
      #   log_errors.each { |e| $log.error e.chomp }
      #   raise(OatsVerifyError, "Found errors in the application logs.")
      # end
      if errors.empty?
        @status = 0 unless @status
        FileUtils.rm Dir[File.join(Oats.data['execution']['run_in_dir_results'] ? result_dir : dir, '*.gen.*')]  \
          if result_dir and (Oats.data('selenium.ide') and not Oats.data('selenium.ide.keep_generated_files') )
      end
    end

    # of run

    def oload_hooks(oats_tsts, pre, obj_msg)
      if rb_file = $oats['execution']['oload_'+pre]
        rb_file = [rb_file] unless rb_file.instance_of?(Array)
        rb_file.reverse! if pre == 'pre'
        rb_file.each do |rbf|
          rbf_fnd = TestCase.locate_test_rb(rbf)
          if rbf_fnd
            oats_tsts.send(obj_msg, rbf_fnd)
          else
            #          eval("self", TOPLEVEL_BINDING).method(:foobar) rescue false
            begin
              Oats.info "Executing oload_#{pre}: #{rbf}"
              eval(rbf)
              #          rescue NoMethodError
            end
            #          if rbf.method?
            #            raise OatsTestError, "Can not locate execution:oload_#{pre} file [#{rbf}]"
            #          end
          end
        end
      end
    end

    private :oload_hooks

    def timed_out?
      @errors.each do |exc|
        # $log.info exc # debug
        return true if exc[0] == 'Timeout::Error'
      end
      return false
    end

    def verify
      return unless Oats.data['execution']['out_verify'] or Oats.data['execution']['ok_verify']
      test_ok_out = ok_out
      test_out = out
      test_ok = ok
      test_result = result
      return if !File.directory?(test_out) and !File.directory?(test_ok_out)
      err = nil
      if !File.directory?(test_out) and File.directory?(test_ok_out)
        err= "Missing test.out folder [#{test_out}], but ok_out folder exists: #{test_ok_out})"
        if Oats.data['execution']['ok_verify'] == 'UPDATE'
          err += " Removing test.ok folder from the test. Please commit it to code repository."
          FileUtils.rm_r(test_ok)
        end
        $log.error(err)
      end
      if File.directory?(test_out) and !File.directory?(test_ok_out)
        err = "Missing test.ok_out folder [#{test_ok_out}], but out folder exists: #{test_out}"
        $log.error(err)
        if Oats.data['execution']['ok_verify'] == 'UPDATE'
          FileUtils.mkdir_p test_ok unless File.directory?(test_ok)
          Dir.chdir(test_result) do
            Dir.glob('*').each { |f| FileUtils.cp_r(f, test_ok) unless f =~ /\.rb$/ }
          end
          $log.warn "Created  test.ok_out folder: #{test_ok_out}"
        end
      end
      if err
        if Oats.data['execution']['ok_verify'].nil?
          ex = OatsVerifyError.exception(err)
          TestData.error(ex)
        elsif Oats.data['execution']['ok_verify'] != 'UPDATE'
          $log.info "Ignoring missing ok directory since Oats.data execution.ok_verify is set"
        end
        return
      end

      error_line = []
      out_files = Dir.entries(test_out)
      ok_out_files = Dir.chdir(test_ok_out) { Dir.glob('*') }
      diff_lines = nil
      out_files.each do |file|
        next if File.directory?(file)
        file_out = File.join(test_out, file)
        file_ok = File.join(test_ok_out, file)
        err = nil
        if File.readable?(file_ok)
          ok_contents = IO.read(file_ok).gsub(/\s/, '')
          out_contents = IO.read(file_out).gsub(/\s/, '')
          unless ok_contents == out_contents
            err = "File in out folder did not match out folder in: #{file_ok}"
            diff_lines = `diff -b '#{file_ok}' '#{file_out}'` unless Oats.os == :windows
          end
        else
          err = "Extra output [#{file}] missing from: #{test_ok_out}"
        end
        if err
          error_line << err
          if Oats.data['execution']['ok_verify'] == 'UPDATE'
            FileUtils.cp(File.join(test_out, file), test_ok_out)
            source = File.join(test_result, file)
            FileUtils.cp(source, test_ok) if File.exist?(source)
            FileUtils.cp(File.join(test_result, 'oats_test.log'), test_ok)
          end
        end
      end
      extra_ok_files = ok_out_files - out_files
      extra_ok_files.each do |f|
        file = File.join(test_ok_out, f)
        FileUtils.rm(file) if Oats.data['execution']['ok_verify'] == 'UPDATE'
        error_line << "Missing output file: #{file}"
      end

      if error_line.empty?
        $log.info "Contents of #{test_ok} matched the output: #{test_out}"
      else
        $log.warn "Differences found in execution.ok_verify:\n\t" +
                      error_line.join("\n\t") +
                      (diff_lines ? "\n" + diff_lines : '')
        if Oats.data['execution']['ok_verify'] == 'UPDATE'
          $log.warn "Contents of #{test_ok} is updated to match the output: #{test_out}"
        elsif Oats.data['execution']['ok_verify'].nil?
          ex = OatsVerifyError.exception(error_line.inspect)
          TestData.error(ex)
          #        raise(OatsVerifyError,error_line.last)
        end
      end
    end

    private :verify

    def TestCase.locate_test_rb(ruby_file_name)
      file = ruby_file_name.sub(/\..*/, '')
      file = File.join($oats['execution']['dir_tests'], '/**/', file+'.rb')
      Dir.glob(file).first
    end

    # Basename of test.dir
    def name
      return @name if @name
      @name = File.basename(@id)
    end

    # Directory under test.result, contains output files to be compared
    def out
      return @out if @out
      @out = File.join(self.result, 'out')
    end

    # Directory of expected results, manually checked in to code repository under test.dir
    def ok
      return @ok if @ok
      raise OatsError, "Test [#{self.id}] does not have a directory" unless @path
      if @is_file
        @ok = @path + '_ok'
      else
        @ok = File.join(@path, 'ok')
      end if @path
    end

    # Directory under test.ok, contains expected result output files
    def ok_out
      return @ok_out if @ok_out
      @ok_out = File.join(self.ok, 'out')
    end
  end

end