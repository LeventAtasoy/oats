# Manages a lock file indicating a OATS session is in process
require 'win32ole' if RUBY_PLATFORM =~ /(mswin|mingw)/
module Oats

  module OatsLock
    @@file_handle = nil
    @@is_locked = false

    # Returns true if able to set the lock.
    def OatsLock.set(verbose = nil)
      if OatsLock.locked?(true)
        return false
      else
        @@file_handle = File.open(in_progress_file, 'w')
        my_pid = Process.pid.to_s
        @@file_handle.puts my_pid
        if RUBY_PLATFORM !~ /(mswin|mingw)/ or ENV['TEMP'] =~ /^\/cygdrive/
          # Leave file handle open for windows to detect and kill associated java, etc.
          # processes using file handles.
          @@file_handle.close
          @@file_handle = nil
        end
        @@is_locked = true
        return true
      end
    end

    # Returns the locked state after the last check
    # verify: true will verify the true state of the lock
    def OatsLock.locked?(verify = nil)
      return @@is_locked unless verify
      @@is_locked = false
      if RUBY_PLATFORM !~ /(mswin|mingw)/ or ENV['TEMP'] =~ /^\/cygdrive/
        if File.exist?(in_progress_file)
          pids = IO.readlines(in_progress_file)
          ruby_pid = pids.shift
          return @@is_locked unless ruby_pid
          ps_line = `ps -p #{ruby_pid} `
          if ps_line =~ /bin\/ruby/
            @@is_locked = true
            $log.error "Another oats session is possibly in progress:"
            $log.error ">> #{ps_line}"
            $log.error "Please kill locking processes or remove #{in_progress_file}."
          else
            pids.each { |pid| OatsLock.kill_pid(pid.chomp) }
            FileUtils.rm(in_progress_file)
          end
        end
      else
        begin
          FileUtils.rm(in_progress_file)
        rescue Errno::ENOENT  # No such File or Directory
        rescue Errno::EACCES  # unlink Permission denied
          @@is_locked = true
          return @@is_locked if verify == :handles_are_cleared
          # Attempt to kill all dangling processes that prevent removal of the lock
          proc_array = nil
          hstring = lock_file
          ok_to_kill = /(java)|(mysql)||(chromedriver)|(firefox)||(chrome)|(iexplore)\.exe/
          pid, proc_name, handle_string, line = nil
          matches = IO.popen("handle #{hstring}").readlines
          oats_is_alive = false
          matches.each do |lvar|
            line = lvar.chomp
            proc_array = parse_windows_handle_process_line(line)
            pid, proc_name, handle_string = proc_array
            next unless pid
            if proc_name =~ /ruby/
              #          if pid = $$.to_s
              #            @@is_locked = false
              #            return false
              #          end
              oats_is_alive = line
              $log.error "Another oats session is possibly in progress:"
              $log.error ">> #{line}"
              $log.error "Please kill locking processes and remove this file if the oats session is defunct."
              break
            end
          end
          @@is_locked = oats_is_alive
          unless oats_is_alive
            matches.each do |lvar|
              line = lvar.chomp
              pid, proc_name, handle_string = parse_windows_handle_process_line(line)
              next unless pid
              raise "Handle error for [#{hstring}] Please notify OATS administrator." unless handle_string =~ /#{hstring}/
              $log.warn "Likely locking process: [#{line}]"
              if proc_name =~ ok_to_kill
                $log.warn "Will attempt to kill [#{proc_name}] with PID #{pid}"
                signal = 'KILL'
                killed = Process.kill(signal,pid.to_i)
                if RUBY_VERSION =~ /^1.9/
                  if killed.empty?
                    killed = 0
                  else
                    killed = 1
                  end
                end
                if killed == 0
                  $log.warn "Failed to kill the process"
                else
                  $log.warn "Successfully killed [#{proc_name}]"
                end
              else
                $log.warn "Oats is configured not to auto-kill process [#{proc_name}]"
              end
            end
            sleep 2  # Need time to clear the process handles
            @@is_locked = OatsLock.locked?(:handles_are_cleared) # Still locked?
          end
          @@is_locked = proc_array if @@is_locked and proc_array
        end
      end
      return @@is_locked
    end

    def OatsLock.kill_pid(pid,info_line=nil)
      signal = 'KILL'
      no_such_process = false
      begin
        killed = Process.kill(signal,pid.to_i)
      rescue Errno::ESRCH # OK if the process is gone
        no_such_process = true
      end
      if RUBY_VERSION =~ /^1.9/
        if killed.empty?
          killed = 0
        else
          killed = 1
        end
      end
      if no_such_process
        #      $log.debug "No such process #{info_line||pid}"
      elsif killed == 0
        $log.warn "Failed to kill [#{info_line||pid}]"
      else
        $log.warn "Successfully killed [#{info_line||pid}]"
      end
    end

    def OatsLock.find_matching_processes(proc_names)
      matched = []
      if RUBY_PLATFORM =~ /(mswin|mingw)/
        processes = WIN32OLE.connect("winmgmts://").ExecQuery("select * from win32_process")
        #      for process in processes do
        #        for property in process.Properties_ do
        #          puts property.Name
        #        end
        #        break
        #      end
        processes.each do |process|
          if process.Commandline =~ proc_names
            matched.push [process.ProcessId,process.Name,nil, process.CommandLine]
          end
        end
      else
        pscom = RUBY_PLATFORM =~ /linux/ ? 'ps lxww' : 'ps -ef'
        `#{pscom}`.split("\n").each do |lvar|
          line = lvar.chomp
          case RUBY_PLATFORM
          when /darwin/ #  ps -ef output
            pid = line[5..11]
            next if pid.to_i == 0
            ppid = line[12..16]
            proc_name = line[50..-1]
          when /linux/ #  ps ww output
            pid = line[7..12]
            next if pid.to_i == 0
            ppid = line[13..18]
            proc_name = line[69..-1]
          else
            raise OatError, "Do not know how to parse ps output from #{RUBY_PLATFORM}"
          end
          next unless pid
          matched.push [pid.strip, proc_name.strip, ppid.strip, line.strip] if proc_name =~ proc_names
        end
      end
      return matched
    end

    def OatsLock.kill_webdriver_browsers
      match = "ruby.*oats/lib/oats_main.rb"
      # Not tested on agents on Windows_NT
      if $oats_execution['agent']
        nickname = $oats_execution['agent']['execution:occ:agent_nickname']
        port = $oats_execution['agent']['execution:occ:agent_port']
        match += " -p #{port} -n #{nickname}"
      end

      # Kill all selenium automation chrome jobs on MacOS. Assumes MacOS is for development only, not OCC.
      # Will cause problems if multiple agents are run on MacOS
      if RUBY_PLATFORM =~ /darwin/
        chrome_automation_procs = OatsLock.find_matching_processes(/ Chrome .* --dom-automation/)
        chrome_automation_procs.each do |pid,proc_name,ppid|
          OatsLock.kill_pid pid
        end
      end

      oats_procs = OatsLock.find_matching_processes(/#{match}\z/)
      chromedriver_procs = OatsLock.find_matching_processes(/IEXPLORE.EXE\" -noframemerging|(chromedriver|firefox(-bin|\.exe\") -no-remote)/)
      webdriver_procs = OatsLock.find_matching_processes(/webdriver/)
      oats_procs.each do |opid,oproc_name,oppid|
        chromedriver_procs.each do |cpid,cproc_name,cppid|
          if cppid == opid
            webdriver_procs.each do |wpid,wproc_name,wppid|
              OatsLock.kill_pid wpid if wppid == cpid
            end
            OatsLock.kill_pid cpid
          end
        end
      end
      # If parent ruby dies, ppid reverts to "1"
      (chromedriver_procs + webdriver_procs).each do |pid,proc_name,ppid|
        OatsLock.kill_pid pid if ppid == "1" and proc_name !~ /defunct/
      end
    end

    # Removes lock
    def OatsLock.reset
      if @@file_handle  # Only for Windows
        @@file_handle.close
        @@file_handle = nil
        @@is_locked = true
      else # Doesn't return status properly for non-windows, just resets the lock
        if $oats_execution['agent'].nil? and RUBY_PLATFORM !~ /(mswin|mingw)/ and File.exist?(in_progress_file)
          pids = IO.readlines(in_progress_file)
          current_pid = pids.shift
          pids.each { |pid| OatsLock.kill_pid(pid.chomp) } # Legacy firefox
        end
        @@is_locked = false
      end
      FileUtils.rm_f in_progress_file
      return @@is_locked
    end

    class << self
      private
      def lock_file
        file =  'oats_in_progress.lock'
        if $oats_execution['agent'] && $oats_execution['agent']['execution:occ:agent_nickname']
          file = $oats_execution['agent']['execution:occ:agent_nickname'] + '_' + file
        end
        return file
      end

      def in_progress_file
        return ENV['HOME'] + '/' + lock_file
      end

      def parse_windows_handle_process_line(line)
        line =~ /(.*) pid:(.*) .*: (.*)/
        return nil unless $1
        proc_name = $1
        pid = $2
        handle_string = $3
        return pid.strip, proc_name.strip, handle_string.strip
      end
    end

  end
end