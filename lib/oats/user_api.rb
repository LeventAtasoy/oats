require 'oats/util'
require 'oats/oats_exceptions'

# Need these set for OCC when this is required from OCC
ENV['OATS_HOME'] ||= File.expand_path( '../..', File.dirname(__FILE__) )
ENV['OATS_TESTS'] ||= (ENV['OATS_HOME'] + '/oats_tests')

module Oats

  # Main method that starts oats execution.
  # Parameters are command-line arguments
  # Returns oats_info object containing execution results
  def Oats.run(args = nil)
    Driver.run(args)
  end

  # Registers classes to initialize class methods by calling call <Class>.init before
  # each TestList execution.  To use, put inside the class: Oats.testlist_init(self)
  def Oats.testlist_init(klas, *args)
    $oats_execution['testlist_init'] ||= {}
    $oats_execution['testlist_init'][klas] = args
  end

  # Merges indicated YAML into the test's Oats.data
  def Oats.yaml(yaml_file)
    OatsData.include_yaml_file yaml_file
  end

  # Adds new test to the current test_files
  # OatsTest.names method(s) should be defined under the OatsTest module in the lib
  # Example:
  # Oats.add_test Oats.add_test "method_test", "testid_#{i}", "parameter_#{i}"
  # module OatsTest # Place this definition in the 'lib' to be auto-required
  #    def self.method_test(params)
  #      Oats.info "Running new test: #{Oats.test.id} with params: #{params.inspect}"
  #    end
  # end
  def Oats.add_test(*args)
    #    Oats.assert self.respond_to?(name), "Method OatsTest.#{names} is not defined."
    #    args[0] = TestData.current_test.dir.sub(/\.rb/,".#{args[0]}.methodTest")

    #    args.unshift TestData.current_test.dir
    $oats_global['test_files'] ||= []
    $oats_global['test_files'].push(args[0])
  end

  # Raises OatsAssertError unless  is includer.include?(includee) is true
  # If given pre_message preceeds the standard message showing expected and actuals.
  # Example:
  # Oats.assert_include('is','this, "Should never fail")
  def Oats.assert_include?(includee, includer, pre_message = nil)
    pre_message += ' ' if pre_message
    Oats.assert(includer.include?(includee),"#{pre_message} Failed since #{includer.inspect} does not include #{includee.inspect}")
  end
  # Raises OatsAssertError unless two parameters are '=='
  # If given pre_message preceeds the standard message showing expected and actuals.
  # Example:
  # Oats.assert_equal(old_count, new_count, "After deletion, creative counts did not decrease.")
  def Oats.assert_equal(expected, actual, pre_message = nil)
    pre_message += ' ' if pre_message
    Oats.assert(expected == actual,"#{pre_message}Expected value #{expected.inspect} does not match actual #{actual.inspect}")
  end
  # Raises OatsAssertError if two parameters are '=='
  def Oats.assert_not_equal(expected, actual, pre_message = nil)
    pre_message += ' ' if pre_message
    Oats.assert(expected != actual,"#{pre_message}Expected different but received the same value: #{actual.inspect}")
  end
  # Raises OatsTestError unless test is true
  def Oats.assert(test, message = nil)
    message = 'Assertion failed.' unless message
    raise(OatsAssertError, message) unless test
  end

  # Returns a browser (selenium driver), logging into RL site or opening URL.
  # The browser is retrieved and reused in the subsequent rtest.*rb executions,
  # but it is automatically closed at the end of each Oats test. If exists, the
  # browser is also accessible via the global $selenium.
  # The arguments url_or_site and credentials will be passed to Oselenium.login
  #
  # Parameters:
  # url_or_site:: String, A URL, or site:
  #                     [root@oats ]
  #               Required parameter for the first invocation, can be
  #               omitted in subsequent invocations to get the current browser.
  #               Re-issueing it w/o logging out of the same site will reopen
  #               the landing page. A different site will cause logout of the
  #               old site and login to the new site. User will be created if
  #               it does not already exists.
  # new_browser:: If true, will create a new browser while keeping the old one.
  # credentials::  Hash to contain credentials['email'] and, credentials['password']
  #
  # Methods in addition to the selenium driver methods are:
  # login(site):: Same as Oats.browser(url_or_site), for a site. Returns nil if
  #               site is not recognized.
  # logout:: Logs out of the last logged in sites if any and returns browser.
  #          Logout may not succeed if logout button is unavailable.
  #
  # Examples:
  #  browser = Oats.browser('oats')
  #  browser.click("link=Orders")
  #  browser.login('root@')
  #  browser.logout
  #
  def Oats.browser(*args)
    require 'oats/oselenium' unless defined?(Oats::Oselenium)
    Oselenium.browser(*args)
  end

  # Capture system screenshot and logs
  # Returns captured file name if successful, or nil.
  def Oats.system_capture
    return if $selenium.nil? or # Snapshots are not supported on Ubuntu/Chrome
    ($oats['selenium']['browser_type'] == 'chrome' and RUBY_PLATFORM =~ /linux/)
    ct = TestData.current_test
    file = Util.file_unique(fn="page_screenshot.png", ct.result)
    Oats.info "Will attempt to capture #{fn}."
    begin
      timeout($oats['selenium']['capture_timeout']) { selenium.save_screenshot(file) }
      ct.error_capture_file = fn
    rescue Exception => e
      $log.warn "Could not capture page screenshot: #{e}"
    end
    return ct.error_capture_file
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
  # across tests. If path is not found, returns nil unless do_raise_if_missing
  # is set.
  #  map_string:: Period seperated YAML path into the current Oats.data
  #    If not specified, returns the full hash.
  #  do_raise_if_missing:: set true to raise OatsTestError if key is missing
  # Examples:
  #  Oats.data 'selenium.browser' == 'firefox
  #  Oats.data['selenium']['browser'] == 'firefox'
  def Oats.data(map_str = nil, do_raise_if_missing = nil)
    return $oats unless map_str
    data_keys = map_str.split('.')
    value = $oats
    #    until ! value.kind_of?(Hash) or data_keys.size == 0 do
    loop do
      return value if data_keys.empty?
      if value.instance_of? Hash
        key = data_keys.shift
        if do_raise_if_missing
          Oats.assert(value.has_key?(key),  "Can not locate #{key} for #{map_str} at ")
        end
        value = value[key]
      else
        return nil
      end
    end
  end

  # Adjust result dir YAML entries if running on agent mode
  def Oats.result_archive_dir
    return $oats['result_archive_dir'] if $oats['result_archive_dir']
    oats_data = $oats
    oats_data['execution']['dir_results'] = Util.expand_path(oats_data['execution']['dir_results'])
    oats_data['result_archive_dir'] = oats_data['execution']['dir_results'] + '_archive'
    if $oats_execution['agent']
      agent_nickname = Ragent.occ['agent_nickname']
      if oats_data['execution']['dir_results'] !~ /#{agent_nickname}$/
        # Should move to a better place.This is unrelated to results, Just picking up the agent file.
        agent_ini_file = File.join(ENV['HOME'], agent_nickname + '_oats.yml')
        oats_data = OatsData.load(agent_ini_file,oats_data) if File.exist?(agent_ini_file)
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

  # Output debug level log entries.
  def Oats.debug(arg)
    $log.debug(arg)
  end

  # Output error level log entries.
  def Oats.error(arg)
    ex = OatsTestError.exception(arg.to_s)
    TestData.error(ex)
    $log.error(arg)
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
  class OatsFilterError  < OatsError ; end

  # Returns Windows file path of a file name to be used with file uploads.
  # name:: globbed file name inside the test directory or under test/data folder.
  # Examples:
  # image = Oats.file "125x125_GIF_4K.gif"
  def Oats.file(name)
    file = name if File.exist?(name)
    file = Dir.glob(File.join(Oats.test.path, name)).first unless file
    file = Dir.glob(File.join( $oats['execution']['dir_tests'], 'data', '**',name)).first unless file
    Oats.assert file, "Can not locate file with name [#{name}]"
    Oselenium.remote_webdriver_map_file_path(file)
  end


  # Moves files downloaded by selenium into the test.result directory.
  # Input is shell glob names, defaulting to '*'.
  # Returns array of basenames of copied files.
  # Assumes downloaded file is not empty
  def Oats.collect_downloaded(file_glob_name = '*')
    downloaded_files = []
    result_dir = TestData.current_test.result
    #    cur_test.collect_downloaded_output if cur_test && cur_test.instance_of?(TestCase)
    Oats.wait_until("There were no files in: #{$oats_global['download_dir']}", 15) do
      Dir.glob(File.join($oats_global['download_dir'],file_glob_name)) do |e|
        # Ensure file is fully downloaded
        old_size = 0
        Oats.wait_until do
          new_size = File.size?(e) # Returns nil if size is zero. Assumes downloaded file is not empty
          if new_size and new_size == old_size # File size stabilized
            FileUtils.mv(e, result_dir )
            downloaded_files.push(File.basename(e))
          else
            old_size = new_size
            false
          end
        end
      end
      downloaded_files != []
    end
    return downloaded_files
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
    raise(OatsFilterError,"At least one inputis required.") unless in_file
    test = TestData.current_test
    case in_file
    when String
      raise(OatsFilterError,"Input string can not be empty.") if in_file == ''
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
        raise(OatsFilterError,"Can not locate file to filter: [#{in_file}] in: " + result_dir) unless filter_file
        raise(OatsFilterError,"Can not read file to filter: #{filter_file}") unless File.readable?(filter_file)
      end
    when Array
      input_is_file = false
      lines = in_file
    else
      raise(OatsFilterError,'Unrecognized input type.')
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
      lines.collect { |line| line.sub!(pattern,replacement) }
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
      out_lines.delete_if{ |line| line.chomp == '' } unless out_lines.empty?
      if out_file and not out_lines.empty?
        File.open(out_file,'a+') { |ios| ios.write(out_lines.join) }
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
  #   file_name: Appends '_<count>' to the this name if the file already exists.
  #   content: String to output, must supply only if a block is not given.
  #   no_raise: If set to true, just return comparison, don't raise exception
  #  Examples:
  # Oats.out_file('my_file.txt', "Check this string" }
  # Oats.out_file('my_file.txt') { |f| f.puts "Check this string" }
  def Oats.out_file(file_name, content = nil, no_raise = nil)
    out_path = Util.file_unique(file_name, Oats.test.result)
    File.open(out_path, 'w+') do |f|
      if block_given?
        yield f
      else
        f.puts content
      end
    end
    Oats.assert(File.exist?(out_path), "Can not find file #{out_path}")  # Verify did create the file
    File.basename(out_path)
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
  def Oats.ide(input_suite_path, hash = nil )
    $ide.run(input_suite_path, hash )
  end

  # Obsolete. Create classes and use class variables to carry over global info.
  def Oats.global
    $oats_global
  end

  # Output info level log entries.
  def Oats.info(arg)
    #    return if arg.nil?
    arg = arg.inspect unless arg.instance_of?(String)
    $log.info(arg)
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
  def Oats.rssh(cmd_file, dir = nil , host = nil, username = nil)
    Ossh.run(cmd_file, dir, host, username )
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

  # Samples the given block each second until it returns true or times out.
  # Raises OatsTestError if times out or returns last value of block.
  #
  # Parameters (also allowed as Hash):
  #  :message  Exception message to issue upon timeout.
  #            Appended with 'in N seconds' unless seconds is negative.
  #  :seconds  For timeout, defaults from Oats.data selenium.command_timeout
  #  :is_return Returns false if times out instead of raising OatsTestError.
  #        If :message is nil, :is_return defaults to true
  #  :interval  Seconds to wait in betweeen calls to block
  #
  # Example:
  #  wait_str = 'loadingIcon'
  #  Oats.wait_until("Page did not have [#{wait_str}]") {
  #    $selenium.get_html_source.include?(wait_str)
  #  }
  def Oats.wait_until(*args)
    raise(OatsTestError, 'Oats.wait_until requires an input block.') unless block_given?
    if args[0].kind_of?(Hash)
      options = args[0]
      message = options[:message]
      seconds = options[:seconds]
      is_return = options[:is_return]
      interval = options[:interval]
    else
      message, seconds, is_return, interval = *args
    end
    interval ||= 1
    seconds ||= Oats.data['execution']['wait_until_timeout']
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
          break if return_val
          sleep interval
        end
        return return_val
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
    prefix = ENV['HOSTNAME'].sub(/\..*/,'').downcase unless prefix or agent
    postfix =  (agent ? agent + '_' : '') + Time.now.to_i.to_s[-8..-1]
    if Oats.global['unique']
      extra = Oats.global['unique'].sub(/#{postfix}/,'')
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
      separator =  '-'
    else
      prefix =  ''
      separator =  ''
    end
    postfix_pattern = separator + (agent ? agent + '_' : '') + '\d\d\d\d\d\d\d\d\d*'
    return prefix.sub(/#{postfix_pattern}$/, '') + separator + "#{postfix}"
  end

  # Output warning level log entries.
  def Oats.warn(arg)
    $log.warn(arg)
  end

end

