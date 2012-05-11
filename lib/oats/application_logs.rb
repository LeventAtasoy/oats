require 'timeout'
require 'oats/ossh'
# Returns all the matching IPs from the listed logs

class ApplicationLogs

  @@app_logs_error_getter = {} # webHostName => ApplicationLogs objects
  @@ip = nil
  @@plink_cmd_params = {} # webHostName => Extra parameters to connect or ''
  PLINK_TIMEOUT = 5

  # Call returns only errors occurring after the previous call.
  def ApplicationLogs.new_errors(initial = false)
    logs = $oats['env']['web']['logs']
    logs = nil if logs.nil? or logs.empty?
    return [] unless logs
    host = $oats['env']['web']['host']
    if @@app_logs_error_getter[host]
      return [] if initial
    else
      @@app_logs_error_getter[host] = ApplicationLogs.new(host,logs)
    end
    return @@app_logs_error_getter[host].new_errors
  end

  def initialize(host,logs)
    ApplicationLogs.set_ip unless @@ip
    @logs = logs
    @log_error_count = []
    @command = "plink #{host} -l loguser sudo grep -i #{@@ip} " + @logs.join(' ')
    ApplicationLogs.set_plink_cmd_params
    @command_issue = @command
  end

  def new_errors
    $log.debug "Interrogating the application logs: #{@command_issue}"
    errors = IO.popen(@command).readlines
    total_errors = 0
    @log_error_count.each {|i| total_errors += i}
    new_error = []
    return new_error if total_errors == errors.length
    i = 0
    new_error_count = []
    new_error_count[0] = 0
    errors.each do |line|
      prefix = Regexp.new('^'+@logs[i]+':')
      unless prefix =~ line
        @log_error_count[i] = new_error_count[i]
        i += 1
        break if i == @logs.length
        new_error_count[i] = 0
        redo
      end
      new_error_count[i] += 1
      new_error << line if new_error_count[i] > (@log_error_count[i] ? @log_error_count[i] : 0)
    end
    @log_error_count[i] = new_error_count[i]
    return new_error
  end

  # Tails logs continuously.
  def ApplicationLogs.tail_errors
    tail_ip = $oats['execution']['tail_logs_ip']
    logs = $oats['env']['web']['logs']
    logs = nil if logs.nil? or logs.empty?
    host = $oats['env']['web']['host']
    if tail_ip
      raise(OatsBadInput, "The execution:tail_logs_ip is set to [#{tail_ip}] but env:web:logs is empty.") unless logs
    else
      return
    end
    if tail_ip and tail_ip.instance_of?(String)
      if /^\d\d\.\d\d*\.\d\d*\.\d\d*$/ =~ tail_ip
        @@ip = tail_ip
      else
        raise(OatsBadInput, "Input for execution:tail_logs_ip [#{tail_ip}] is not in proper IP format.")
      end
    else
      ApplicationLogs.set_ip unless @@ip
    end
    ApplicationLogs.set_plink_cmd_params(true)
    command = "plink #{host} -l loguser sudo tail -f " + logs.join(' ')
    command_issue = command
    puts "Filtering for [#{@@ip}] after executing command: #{command}"
    IO.popen(command_issue) do |io|
      while io.gets do
        puts $_ if Regexp.new(@@ip) =~ $_ or /^==>/ =~ $_
      end
    end
    exit 0 # Should never get here. User has to kill the process to quit
  end

  def ApplicationLogs.set_plink_cmd_params(from_tail = nil)
    host = $oats['env']['web']['host']
    return if @@plink_cmd_params[host]
    # Ossh does not support this option anymore. Must go in via Paegant
    # Clean-up the code below later.
    @@plink_cmd_params = ''
    error = 0
    error_msg = nil
    error_msg2 = nil
    correct_response = false
    cmd_issue = "plink #{host} -l loguser whoami 2>&1"
    cmd_display = cmd_issue
    $log.debug "Issuing: " + cmd_issue
    $log.debug "Please start Paegant with loguser key if there is no response in {PLINK_TIMEOUT} seconds."
    begin
      timeout(PLINK_TIMEOUT) do
        IO.popen(cmd_issue) do |ios|
          while ios.gets(':') do
            if /s password:/ =~ $_
              error = 1
              error_msg = "Received Plink authentication challenge from "
              error_msg2 = "If you have not started Paegant already, please do so."
            elsif /s password:/ =~ $_
              error = 2
              error_msg = "Received Plink authentication challenge from "
              error_msg2 = "If you have not defined an entry for [#{host} on Putty already, please do so."
            elsif /^Password:/ =~ $_
              error = 3
              error_msg = "Received 'sudo root' authentication challenge from "
              error_msg2 = "Sudo password cash has timed out. Please type the following on a shell commandline: #{cmd_display}"
            elsif /^Unable to open connection:/ =~ $_
              error = 4
              error_msg = "Could not connect to "
              error_msg2 = "You need to unset error log interrogation to run this test in this environment."
#            elsif /^root/ =~ $_
            elsif /^loguser/ =~ $_
              correct_response = true
            end
            $log.error $_ unless $_.nil? or correct_response
            ios.gets
            $log.error $_ unless $_.nil? or correct_response
          end
        end
      end
    rescue Timeout::Error
      $log.error "plink command timed out after [#{PLINK_TIMEOUT}] seconds."
    end
    if error == 0 and correct_response
      $log.info "Received proper response from Plink."
      return
    else
      if error_msg
        if error_msg2
          $log.error error_msg + "[#{host}]"
        else
          raise(OatsSetupError,error_msg)
        end
        raise(OatsSetupError,error_msg2)
      end
    end
  end

  def ApplicationLogs.set_ip
    IO.popen('ipconfig') do |io|
      while io.gets do
        @@ip = $_.chomp.sub(/.*IP Address.*: (\d.*\d).*/,'\1') if /IP Address.*: / =~ $_
      end
    end
  end

end
