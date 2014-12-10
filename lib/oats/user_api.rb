require_relative 'oats_exceptions'
require 'fileutils'
require 'timeout'
require 'rbconfig'

# Need these set for OCC when this is required from OCC
ENV['OATS_HOME'] = ENV['OATS_HOME'] ? ENV['OATS_HOME'].gsub('\\', '/') : File.expand_path('../..', File.dirname(__FILE__))
ENV['OATS_TESTS'] = ENV['OATS_TESTS'] ? ENV['OATS_TESTS'].gsub('\\', '/') : (ENV['OATS_HOME'] + '/oats_tests')
module Oats

  # Main method that starts oats execution.
  # Parameters are command-line arguments
  # Returns oats_info object containing execution results
  def Oats.run(args = nil)
    Driver.run(args)
  end

  # Registers a class to (re)initialize class variables by calling call <Class>.init before
  # each Oats execution.  To use, put inside the class: Oats.init(self)
  # Last test can also set a handler_post_test_list to [Class.init], but a test cannot set handler_pre_test_list.
  def Oats.init(klas, *args)
    $oats_execution['oats_init'] ||= {}
    $oats_execution['oats_init'][klas] = args
  end

  # Merges indicated YAML into the test's Oats.data
  def Oats.yaml(yaml_file)
    OatsData.include_yaml_file yaml_file
  end

  # Adds new test to the current test_files. Test can be
  # MyTest.method(s) should be defined under in a module in the lib
  # Example:
  # Oats.add_test ['MyTest.method_test'] # Creates a test_id with this method
  def Oats.add_test(*args)
    $oats_global['test_files'] ||= []
    $oats_global['test_files'].push(args[0])
  end

  # Raises OatsAssertError unless  is includer.include?(includee) is true
  # If given pre_message preceeds the standard message showing expected and actuals.
  # Example:
  # Oats.assert_include('is','this, "Should never fail")
  def Oats.assert_include?(includee, includer, pre_message = nil)
    pre_message += ' ' if pre_message
    Oats.assert(includer.include?(includee), "#{pre_message} Failed since #{includer.inspect} does not include #{includee.inspect}")
  end

  # Raises OatsAssertError unless two parameters are '=='
  # If given pre_message preceeds the standard message showing expected and actuals.
  # Example:
  # Oats.assert_equal(old_count, new_count, "After deletion, creative counts did not decrease.")
  def Oats.assert_equal(expected, actual, pre_message = nil)
    pre_message += ' ' if pre_message
    Oats.assert(expected == actual, "#{pre_message}Expected value #{expected.inspect} does not match actual #{actual.inspect}")
  end

  # Raises OatsAssertError if two parameters are '=='
  def Oats.assert_not_equal(expected, actual, pre_message = nil)
    pre_message += ' ' if pre_message
    Oats.assert(expected != actual, "#{pre_message}Expected different but received the same value: #{actual.inspect}")
  end

  # Raises OatsTestError unless test is true
  def Oats.assert(test, message = nil)
    message = 'Assertion failed.' unless message
    raise(OatsAssertError, message) unless test
  end


  # Loads the indicated ruby file file after locating it in the tests directory.
  #
  # Parameters:
  # ruby_file_name: Name or path snippet of a the ruby file. Could be a glob.
  #
  # Examples:
  #  Oats.oload 'rtest_AddCreatives'
  #  Oats.oload 'verifyAddCreatives/rtest_Add*'
  def Oats.oload(ruby_file_name)
    file = TestCase.locate_test_rb(ruby_file_name)
    if file
      begin
        Oats.debug "Loading rb file: #{file}"
        Oats.global['oloads'].push file
        load(file)
      ensure
        Oats.debug "Finished rb file: #{file}"
        Oats.global['oloads'].pop
      end
    else
      raise OatsError, "Can not locate ruby file to load: #{ruby_file_name}"
    end
  end

  # Hash object providing access to the oats.yml state entries at the time of
  # test execution. Note that Oats.data contents are isolated from modification
  # across tests. If path is not found, returns nil, unless do_raise_if_missing
  # is set, then raises OatsTestError
  # Parameters:
  #  :map_string:: [String[ Period seperated YAML path into the current Oats.data
  #    If not specified, returns the full hash.
  #  :param2: if
  #     * [Hash] use this hash instead of standard Oats.data]
  #     * [True] use it as do_raise_if_missing
  #     * [Symbol] to use with opt
  #  :param3-4:
  #     Meaning depends on param3.  See Examples below
  #
  # Examples:
  #  # No Param2
  #  Oats.data('My')['data'] = 'value' # Setting a value
  #  Oats.data 'My.data' == 'value'    # Accessing the value
  #  Oats.data 'My.non_existing_data' # returns nil
  #
  #  # Param2 is True
  #  Oats.data 'My.non_existing_data', true # raises OatsTestError
  #
  #  # Param2 is a Hash
  #  Oats.data 'My.data', {My => {data => value}}  # returns value
  #
  #  # Param2 is Symbol
  #  Oats.data 'My', :data  # returns  Oats.data(My.data)
  #  Oats.data 'My', :data, option  # Returns (option[:data] || Oats.data(My.data)), but raises if missing key
  #  Oats.data 'My', :data, option ,true #  But also raises if result is nil
  def Oats.data(map_str = nil, param2 = nil, param3 = nil, param4 = nil)
    return $oats unless map_str
    sym = nil
    if param2.instance_of?(Hash)
      value = param2
      do_raise_if_missing = param3
    elsif param2.instance_of?(Symbol)
      value = $oats
      sym = param2
      opt = param3
      do_raise_if_missing = param4
    else
      value = $oats
      do_raise_if_missing = param2
    end
    if sym
      return opt[sym] if opt and opt[sym]
      map_str = "#{map_str}.#{sym}"
    end
    data_keys = map_str.split('.')
    loop do
      if data_keys.empty?
        if sym.nil?
          return value
        else
          Oats.assert(value, 'Need to specify Oats.data: ' + map_str) if opt and do_raise_if_missing
          return value
        end
      end
      if value.instance_of? Hash
        key = data_keys.shift
        if do_raise_if_missing
          Oats.assert(value.has_key?(key), "Can not locate #{key} for #{map_str} at ")
        end
        value = value[key]
      else
        return nil
      end
    end
  end

  # Shallow merge Oats.data(map_str) to options, merging symbols keys in options into string keys in Oats.data
  def Oats.data_merge(options, map_str)
    opt = options.dup
    opt.deep_merge(Oats.data(map_str))
    opt.each_key do |k|
      if k.instance_of? Symbol
        opt[k.to_s] = opt.delete(k)
      end
    end
    opt
  end

  # Adjust result dir YAML entries if running on agent mode
  def Oats.result_archive_dir
    return $oats['result_archive_dir'] if $oats['result_archive_dir']
    oats_data = $oats
    oats_data['execution']['dir_results'] = Util.expand_path(oats_data['execution']['dir_results'])
    oats_data['result_archive_dir'] = oats_data['execution']['dir_results'] + '_archive'
    if $oats_execution and $oats_execution['agent']
      agent_nickname = OatsAgent::Ragent.occ['agent_nickname']
      if oats_data['execution']['dir_results'] !~ /#{agent_nickname}$/
        # Should move to a better place.This is unrelated to results, Just picking up the agent file.
        agent_ini_file = File.join(ENV['OATS_USER_HOME'], agent_nickname + '_oats.yml')
        oats_data = OatsData.load(agent_ini_file, oats_data) if File.exist?(agent_ini_file)
        oats_data['result_archive_dir'] += '/' + agent_nickname
        oats_data['execution']['dir_results'] += '/' + agent_nickname
      end
    end
    FileUtils.mkdir_p(oats_data['result_archive_dir'])
    return oats_data['result_archive_dir']
  end

  # Returns input. Used to force ruby eval of Oat.data YML values
  def Oats.eval(input=nil)
    return input
  end

  # Returns hash object containing info about persistent oats internal variables
  # for the complete oats execution. Contents of Oats.context are also persisted  into
  # the results.dump in the results directory.
  #
  # Examples:
  #  Oats.context['stop_oats'] == true #  Request stopping oats after current test
  def Oats.context
    $oats_info
  end

  # Exit a OATS Test from the middle without throwing an error.
  def Oats.exit(message=nil)
    raise OatsTestExit, message if message
    raise OatsTestExit
  end

  # Raise OatsTestExit and SKIP current test if there was a previous test and
  # if previous test dif not pass or or_if_true is true
  def Oats.skip_unless_previous_test_is_ok(or_if_true = false)
    return unless TestData.previous_test
    if or_if_true or TestData.previous_test.status != 0
      Oats.data['execution']['no_run'] = true
      Oats.exit "Skipping this test since previous test did not pass."
    end
  end

  # Exception raised by Oats.filter
  class OatsFilterError < OatsError;
  end

  # Returns Windows file path of a file name to be used with file uploads.
  # name:: globbed file name inside the test directory or under test/data folder.
  # Examples:
  # image = Oats.file "125x125_GIF_4K.gif"
  def Oats.file(name)
    file = name if File.exist?(name)
    file = Dir.glob(File.join(Oats.test.path, name)).first unless file
    file = Dir.glob(File.join($oats['execution']['dir_tests'], 'data', '**', name)).first unless file
    Oats.assert file, "Can not locate file with name [#{name}]"
#    Oselenium.remote_webdriver_map_file_path(file)
    file
  end


  # Removes the random words from files in 'Oats.test.result' by applying
  # prescribed filter to each line of file and replaces it.  The return value is
  # the filtered contents of the file. The filtered contents are also placed in
  # test.out to be compared as expected results. Errors will raise OatsFilterError.
  # * With a block replaces each line with result of the block.
  # * Without block, uses a pattern and replacement parameters for filtering.
  # * If pattern and replacement is missing it copies the whole input file.
  # * If in_file is a string, no output file is generated unless out_file is given.
  #
  # Parameters:
  # in_file:: Name or path of file that is to be filtered and moved to
  #	          Oats.test.out.  It can also be String Array or String containing the
  #	          actual contents. If the file contains a space, it is assumed to be
  #	          contents. Missing input or file raises OatsFilterError.
  # out_file:: File name to use for the output file. This is an optional
  #            parameter which can be skipped. If skipped, basename of the
  #            infile is used.
  # pattern:: A regexp pattern to pass on to a gsub or grep method.  Grep is
  #	          used if replacement parameter is unspecified, in other words
  #	          file_contents.grep(/pattern_string/)
  # replacement:: Fixed string to replace the pattern by calling
  #	              file_contents.gsub(pattern,replacement)
  #
  # Examples:
  #  Oats.filter('input.txt') # Moves input.txt to test.out for auto-verification.
  #  Oats.filter('input.txt','output.txt,/this/) # Considers only lines containing 'this'
  #  Oats.filter('input.txt',/this.*that/,'thisAndThat') # Replaces indicated content
  #  Oats.filter('input.txt') { |line| line unless line == 'this\n' } # Omits 'this\n' line
  def Oats.filter(in_file, *param)
    raise(OatsFilterError, "At least one inputis required.") unless in_file
    test = TestData.current_test
    case in_file
      when String
        raise(OatsFilterError, "Input string can not be empty.") if in_file == ''
        if /\s/ =~ in_file # If there is space in name, assume it is not a file
          input_is_file = false
          lines = in_file.split($/)
        else
          input_is_file = true
          if File.exist?(in_file)
            filter_file = Util.expand_path(in_file)
          else
            in_files = Dir[in_file]
            filter_file = in_files[0] unless in_files.empty?
          end
          unless filter_file
            result_dir = test.result
            filter_file = Util.expand_path(in_file, result_dir)
            filter_file = nil unless File.exist?(filter_file)
          end
          unless filter_file
            filter_file = Util.expand_path(in_file, result_dir)
            in_files = Dir[filter_file]
            if in_files.empty?
              filter_file = nil
            else
              filter_file = in_files[0]
            end
          end
          raise(OatsFilterError, "Can not locate file to filter: [#{in_file}] in: " + result_dir) unless filter_file
          raise(OatsFilterError, "Can not read file to filter: #{filter_file}") unless File.readable?(filter_file)
        end
      when Array
        input_is_file = false
        lines = in_file
      else
        raise(OatsFilterError, 'Unrecognized input type.')
    end

    if not param.empty? and param[0].instance_of?(String)
      out_file = File.join(test.out, File.basename(param[0]))
      param.shift
    elsif input_is_file
      out_file = File.join(test.out, File.basename(filter_file))
    else
      out_file = nil
    end
    FileUtils.mkdir_p(test.out) if test.out
    if param.empty?
      pattern = nil
    else
      pattern = param[0]
      param.shift
    end
    if param.empty?
      replacement = nil
    else
      replacement = param[0]
      param.shift
    end
    lines = IO.readlines(filter_file) if input_is_file
    #      FileUtils.rm(filter_file)
    out_lines = if block_given?
                  lines.collect { |line| yield(line) }
                elsif replacement
                  lines.collect { |line| line.sub!(pattern, replacement) }
                elsif pattern
                  lines.grep(pattern)
                else
                  if out_file and filter_file
                    FileUtils.cp(filter_file, out_file) # Do not mv here.
                    # Otherwise out_file can not produce unique files
                    return lines ? lines : []
                  end
                  lines ? lines : []
                end

    if out_lines
      out_lines.delete_if { |line| line.chomp == '' } unless out_lines.empty?
      if out_file and not out_lines.empty?
        File.open(out_file, 'a+') { |ios| ios.write(out_lines.join) }
      end
    else
      out_lines = []
    end
    out_lines
  end

  # Creates a file handle to output into the out directory with given name
  # Returns the comparison with any previous ok file if exists.
  #
  # Parameters:
  #   file_name:: Appends '_<count>' to the this name if the file already exists.
  #   content:: String to output, must supply only if a block is not given.
  #   no_raise:: If set to true, just return comparison, don't raise exception
  # Examples:
  #  Oats.out_file('my_file.txt', "Check this string" }
  #  Oats.out_file('my_file.txt') { |f| f.puts "Check this string" }
  # @return [String] Full path of the output file
  def Oats.out_file(file_name, content = nil, no_raise = nil)
    out_path = Util.file_unique(file_name, Oats.test.result)
    File.open(out_path, 'w+') do |f|
      if block_given?
        yield f
      else
        f.puts content
      end
    end
    Oats.assert(File.exist?(out_path), "Can not find file #{out_path}") # Verify did create the file
    out_path
    #File.basename(out_path)
    #    file_ok = File.join Oats.test.ok_out, basename
    #    is_ok = true
    #    if File.exist?(file_ok)
    #      is_ok  = FileUtils.compare_file(out_path, file_ok)
    #      Oats.assert is_ok || no_raise, "Found differences in file: #{file_ok}"
    #      Oats.info "Matched ok contents [#{content||basename}"
    #    end
    #    return is_ok
  end


  # Runs the input_suite_path from a particular Oats.test. Assumes Oats.data is
  # initialized for Oats.test
  #
  # Parameters:
  # input_suite_path:: path to the IDE suite HTML
  # hash:: list from => to values to use for regeneration of the included test
  # cases.
  #
  # Examples:
  #  Oats.ide.run('../campaign/rtest.html', 'this_token" => 'that_value')
  def Oats.ide(input_suite_path, hash = nil)
    $ide.run(input_suite_path, hash)
  end

  # for inter-test data, within a TestList. Using class variables carries data across TestLists.
  def Oats.global(par=nil)
    return $oats_global unless par
    Oats.data(par, $oats_global)
  end


  # Execute MySQL files or statements, return result set in an array of rows.
  # Empty result set results in an empty array. First row [0] of the result
  # contains the column headers. If each row has multiple fields, the row is
  # returned in an array of strings. Otherwise each row a string containing the
  # single column value.
  #
  # Parameters:
  #  sql_input:: String denoting a file or SQL content (assumed if s has a space)
  #  connect::   Override for Oats.data sql:connect
  #  sql_out_name:: File name to place the SQL output into the test.out directory.

  # Examples
  #  Oats.mysql('input.sql')  => produces input.txt and returns its contents
  #  Oats.mysql('input.sql', 'output.txt)  => produces output.txt and returns its contents
  #  mysql_results = Oats.mysql "SELECT bu_lastname, FROM BusinessUser where bu_email='levent.atasoy@oats.org;XYZ'"
  #  result = Oats.mysql(my_sql_statement)
  #  result.is_empty? # true if SQL returns nothing
  #  result.last # string value for the last row of a single select statement
  #  result[1][2] # second column for the first return result row

  def Oats.mysql(*sql_input)
    require 'oats/mysql' unless defined?(Oats::Mysql) == 'constant'
    $mysql ||= Oats::Mysql.new
    $mysql.run(*sql_input)
  end

  #  Executes a script on an server via ssh using PuTTy/plink
  #  Assumes pageant with keys for the username is up and running.
  #  Returns the result of the standard output and standard error.
  #
  # Parameters:
  # cmd_file:: Path of the executable relative to dir
  # dir:: Directory to cd prior to executing cmd_file. Home of user if omitted.
  # host/session: Name for putty on which to execute cmd_file. Defaults via Oats.data
  # username:: Putty connection data Login username. Defaults via Oats.data.
  #       If username is 'root', executes the cmd_file as sudo root with
  #       Oats.data[ssh.root_sudo_username].
  #       root_sudo_username must be able to
  #        - access host via Plink/Pageant
  #        - sudo -s on the host
  #        - cd to dir without being root.
  #
  # Examples
  #  out = Oats.rssh('/home/transfer.pl')
  #  Oats.rssh('./transfer.pl', /home')
  #  Oats.rssh('cat that.log','/var/www/app')
  #  Oats.rssh('ls httpd', '/var/log', nil, 'root')
  def Oats.rssh(cmd_file, dir = nil, host = nil, username = nil)
    Ossh.run(cmd_file, dir, host, username)
  end

  #  Copies a file to the server via ssh using PuTTy/plink
  #  Assumes pageant with keys for the username is up and running.
  #  Returns the result of the standard output and standard error, which is
  #  typically empty.
  #
  # Parameters:
  # content_file:: Path of the content file, or the content string if file
  #       does not exist.
  # target_file_path:: Path of the file on the server
  # host/session: Same parameter as in Oats.rssh
  # username:: Same parameter as in Oats.rssh
  #
  # Examples
  #  Oats.rput 'xxx     xxxxxxx', '/tmp/myfile.txt' , 'qapp001.dyn.wh.oats.org'
  #  Oats.rput 'c:/qa/oats-user.yml', '/tmp/myfile.txt' , 'qapp001.dyn.wh.oats.org'
  def Oats.rput(content_file, target_file_path = nil, host = nil, username = nil)
    Ossh.run(content_file, target_file_path, host, username, true)
  end

  # Returns the current TestData object. You can use the public instance methods
  # of TestCase to access to test path components or other test information.
  def Oats.test
    TestData.current_test
  end

  # Stores an object for the test_name to be retrived by subsequent tests via Oats.test_data
  # @param [object] value to be stored as part of current test
  def Oats.test_data=(value)
    Oats.global['test_data'][TestData.current_test.name] = value
  end

  # Retrieves the data save in a previous test_name via Oats.test_data=
  # @param [String] test_name in the same the test list that was executed earlier
  # @return [object] value stored previously during the execution of test_name
  def Oats.test_data(test_name)
    Oats.global['test_data'][test_name]
  end

  # Samples the given block each second until it returns true or times out.
  # Raises OatsTestError if times out or returns last value of block.
  #
  # Parameters (also allowed as Hash):
  #  :message::  Exception message to issue upon timeout.
  #              Appended with 'in N seconds' unless seconds is negative.
  #  :seconds::  For timeout, defaults from Oats.data 'execution.wait_until_timeout'.
  #              Use -sec to append timeout to the message
  #  :is_return:: Returns false if times out instead of raising OatsTestError.
  #        If :message is nil, :is_return defaults to true
  #  :interval::  Seconds to wait in between calls to block
  #
  # Examples:
  #  wait_str = 'loadingIcon'
  #  Oats.wait_until("Page did not have [#{wait_str}]") {
  #    $selenium.get_html_source.include?(wait_str)
  #  }
  def Oats.wait_until(*args)
    raise(OatsTestError, 'Oats.wait_until requires an input block.') unless block_given?
    options = args.last.instance_of?(Hash) ? args.pop : {}
    message, seconds, is_return, interval = *args
    message ||= options[:message]
    seconds ||= options[:seconds] || Oats.data('execution.wait_until_timeout')
    is_return = options[:is_return]
    interval ||= options[:interval] || 1
    is_return = true if message.nil?
    if seconds < 0
      seconds = seconds.abs
      message += " in #{seconds} seconds"
    end
    begin
      return_val = false
      Timeout::timeout seconds do
        loop do
          return_val = yield
          return return_val if return_val
          sleep interval
        end
      end
    rescue Timeout::Error
      if is_return
        Oats.warn message if message
        return false
      else
        raise(OatsTestError, message) if message
        raise OatsTestError
      end
    end
  end

  # Returns a unique string for each machine for each call.
  # The string will start with the input prefix if supplied.
  # If the input prefix matches the pattern of unique output, then only the
  # unique suffix is modified.
  #
  # Parameters:
  # prefix:: Prefix string to use.
  #
  # Examples:
  #  Oats.unique          => "mach_83580508"
  #  Oats.unique('this')  => "this-835805081"
  #  Oats.unique(Oats.unique('this'))  => "this-835805082"
  def Oats.unique(prefix = nil)
    agent = $oats_execution['agent'] ? $oats_execution['agent']['execution:occ:agent_nickname'] : nil
    prefix = ENV['HOSTNAME'].sub(/\..*/, '').downcase unless prefix or agent
    postfix = (agent ? agent + '_' : '') + Time.now.to_i.to_s[-8..-1]
    if Oats.global['unique']
      extra = Oats.global['unique'].sub(/#{postfix}/, '')
      unless extra == Oats.global['unique']
        if extra == ''
          postfix = "#{postfix}1"
        else
          postfix = postfix + ((extra.to_i) + 1).to_s
        end
      end
    end
    Oats.global['unique'] = postfix
    if prefix
      separator = '-'
    else
      prefix = ''
      separator = ''
    end
    postfix_pattern = separator + (agent ? agent + '_' : '') + '\d\d\d\d\d\d\d\d\d*'
    return prefix.sub(/#{postfix_pattern}$/, '') + separator + "#{postfix}"
  end

  # Output info level log entries.
  def Oats.info(arg, level=nil)
    if level.nil?
      return if LOG_LEVEL.index(Oats.data('execution.log_level')) > 1
      level = 'info'
    end
    arg = arg.inspect unless arg.instance_of?(String)
    if $log
      $log.send(level, arg)
    else
      out = (level == 'error' ? $stderr : $stdout)
      out.puts Time.now.strftime('%F %T') + " [#{level.upcase}] #{arg}"
    end
  end

# Output warning level log entries.
  def Oats.warn(arg)
    Oats.info(arg, 'warn') if LOG_LEVEL.index(Oats.data('execution.log_level')) < 3
  end

# Output debug level log entries.
  def Oats.debug(arg)
    Oats.info(arg, 'debug') if LOG_LEVEL.index(Oats.data('execution.log_level')) < 1
  end

  LOG_LEVEL = %w(DEBUG INFO WARN ERROR FATAL)
# Set logging level
  def self.log_level=(level)
    Oats.data('execution')['log_level']= level
  end

# Output error level log entries.  Argument should respond to to_s.
  def Oats.error(arg)
    if defined?(TestData)
      ex = OatsTestError.exception(arg.to_s)
      TestData.error(ex)
    end
    Oats.info(arg, 'error') if LOG_LEVEL.index(Oats.data('execution.log_level')) < 4
  end

  def self.os
    @os ||= (
    host_os = RbConfig::CONFIG['host_os']
    case host_os
      when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
        :windows
      when /darwin|mac os/
        :macosx
      when /linux/
        :linux
      when /solaris|bsd/
        :unix
      else
        raise Error::WebDriverError, "unknown os: #{host_os.inspect}"
    end
    )
  end

  # Called by default by the system when uncaught exceptions occur in oats.
  # Takes the desktop screen_capture followed by Selenium page capture if it exists.
  def self.system_capture
    Util::screen_capture
    defined?(Oats::Selenium) and Oats::Selenium.respond_to?(:system_capture) and
        !Oats.data['selenium']['skip_capture'] and
        Selenium.system_capture  # Overrides the current_test.error_file of screen_capture if it works
  end

end

require_relative 'util'
