# Manages a lock file indicating a OATS session is in process
require 'win32ole' if Oats.os == :windows
require_relative 'util'
module Oats

  class FileLock
    attr_accessor :lock_file # used to set the lock file in between

    def initialize(file)
      if file[0] == '/'
        @lock_file = file
      else
        lock_dir = ENV[' TMP '] || '/tmp'
        Oats.assert lock_dir, "TMP"
        # if lock_dir.nil? and Oats.os != :windows or ENV['TEMP'] =~ /^\/cygdrive/
        @lock_file = File.join(lock_dir, file)
      end
    end

    # Returns returns existing lock file contents or nil if it succeeds in setting a new one.
    def check_set(process_arg=nil)
      is_locked = locked?
      return is_locked if is_locked
      @file_handle = File.open(lock_file, 'w')
      my_pid = Process.pid.to_s
      my_pid += ',' + process_arg if process_arg
      @file_handle.puts(my_pid)
      if Oats.os != :windows or ENV['TEMP'] =~ /^\/cygdrive/
        # Leave file handle open for windows to detect and kill associated java, etc.
        # processes using file handles.
        @file_handle.close
        @file_handle = nil
        out = File.readlines(lock_file)
        return out unless out[0].chomp == my_pid.to_s
      end
      return nil
    end

    # Returns nil if not locked, or contents of the lock file if locked.
    def locked?(verbose = nil)
      busy_file = lock_file
      is_locked = nil
      if Oats.os != :windows or ENV['TEMP'] =~ /^\/cygdrive/
        if File.exist?(busy_file)
          pid_lines = IO.readlines(busy_file)
          pid_line = pid_lines.shift.chomp.split(',')
          pid = pid_line[0]
          ps_args = pid_line[1]
          ps_line = `ps -p #{pid}`
          ps_args = pid unless ps_args
          if  ps_line =~ /#{ps_args}/
            is_locked = ps_line.chomp
            if verbose
              Oats.error "Another session is possibly in progress:"
              Oats.error ">> #{ps_line}"
              Oats.error "Please kill locking processes or remove #{busy_file}."
            end
          else
            # Should not be a PID to kill. An active PID should have been caught above already
            # killed = Util.kill(pid)

            # raise "Process should have been defunct but Unexpectedly killed #{pid} for pid_line." unless killed.empty?
            # The line below should not execute unless multiple PIDs registered in the flag file
            # pid_lines.each { |pid_line| Util.kill(pid._line.chomp.split(',')[0]) }
            Oats.warn "Resetting the defunct lock flag file for #{pid_line}: #{busy_file}"
            FileUtils.rm(busy_file)
          end
        end
      else
        raise 'Not implemented'
        begin
          FileUtils.rm(busy_file)
        rescue Errno::ENOENT # No such File or Directory
        rescue Errno::EACCES # unlink Permission denied
          is_locked = true
          return is_locked if verify == :handles_are_cleared
          # Attempt to kill all dangling processes that prevent removal of the lock
          proc_array = nil
          hstring = busy_file
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
              #            is_locked = false
              #            return false
              #          end
              oats_is_alive = line
              Oats.error "Another oats session is possibly in progress:"
              Oats.error ">> #{line}"
              Oats.error "Please kill locking processes and remove this file if the oats session is defunct."
              break
            end
          end
          is_locked = oats_is_alive
          unless oats_is_alive
            matches.each do |lvar|
              line = lvar.chomp
              pid, proc_name, handle_string = parse_windows_handle_process_line(line)
              next unless pid
              raise "Handle error for [#{hstring}] Please notify OATS administrator." unless handle_string =~ /#{hstring}/
              Oats.warn "Likely locking process: [#{line}]"
              if proc_name =~ ok_to_kill
                Oats.warn "Will attempt to kill [#{proc_name}] with PID #{pid}"
                signal = 'KILL'
                killed = Process.kill(signal, pid.to_i)
                if RUBY_VERSION =~ /^1.9/
                  if killed.empty?
                    killed = 0
                  else
                    killed = 1
                  end
                end
                if killed == 0
                  Oats.warn "Failed to kill the process"
                else
                  Oats.warn "Successfully killed [#{proc_name}]"
                end
              else
                Oats.warn "Oats is configured not to auto-kill process [#{proc_name}]"
              end
            end
            sleep 2 # Need time to clear the process handles
            is_locked = OatsLock.locked?(:handles_are_cleared) # Still locked?
          end
          is_locked = proc_array if is_locked and proc_array
        end
      end
      return is_locked
    end

    # Removes lock, return current locked state
    def reset
      busy_file = lock_file
      if @file_handle # Only for Windows
        @file_handle.close
        @file_handle = nil
        is_locked = true
      else # Doesn't return status properly for non-windows, just resets the lock
        if ($oats_execution.nil? or $oats_execution['agent'].nil?) and Oats.os != :windows and File.exist?(busy_file)
          pids = IO.readlines(busy_file)
          current_pid = pids.shift
          pids.each { |pid| Util.kill(pid.chomp) } # Legacy firefox
        end
        is_locked = false
      end
      FileUtils.rm_f busy_file
      return is_locked
    end

    private

    # def lock_file
    #   file = 'oats_in_progress.lock'
    #   if $oats_execution['agent'] && $oats_execution['agent']['execution:occ:agent_nickname']
    #     file = $oats_execution['agent']['execution:occ:agent_nickname'] + '_' + file
    #   end
    #   return file
    # end

  end
end
