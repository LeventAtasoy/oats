# Manages a lock file indicating a OATS session is in process
require 'win32ole' if RUBY_PLATFORM =~ /(mswin|mingw)/
require_relative 'util'
module Oats

  class FileLock

    class << self

      attr_accessor :lock_file

      # Returns returns existing lock file contents or nil if it succeeds in setting a new one.
      def check_set(process_arg=nil)
        is_locked = locked?
        return is_locked if is_locked
        @file_handle = File.open(lock_file, 'w')
        my_pid = Process.pid.to_s
        my_pid += ',' + process_arg if process_arg
        @file_handle.puts(my_pid)
        if RUBY_PLATFORM !~ /(mswin|mingw)/ or ENV['TEMP'] =~ /^\/cygdrive/
          # Leave file handle open for windows to detect and kill associated java, etc.
          # processes using file handles.
          @file_handle.close
          @file_handle = nil
        end
        return nil
      end

      # Returns nil or contents of the lock file
      def locked?(verbose = nil)
        is_locked = nil
        if RUBY_PLATFORM !~ /(mswin|mingw)/ or ENV['TEMP'] =~ /^\/cygdrive/
          if File.exist?(lock_file)
            pid_lines = IO.readlines(lock_file)
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
                Oats.error "Please kill locking processes or remove #{lock_file}."
              end
            else
              # Should not be a PID to kill. An active PID should have been caught above already
              # killed = Util.kill(pid)
              # raise "Process should have been defunct but Unexpectedly killed #{pid} for pid_line." unless killed.empty?
              # The line below should not execute unless multiple PIDs registered in the flag file
              # pid_lines.each { |pid_line| Util.kill(pid._line.chomp.split(',')[0]) }
              Oats.warn "Resetting the defunct flag file for: #{pid_line}"
              FileUtils.rm(lock_file)
            end
          end
        else
          raise 'Not implemented'
          begin
            FileUtils.rm(lock_file)
          rescue Errno::ENOENT # No such File or Directory
          rescue Errno::EACCES # unlink Permission denied
            is_locked = true
            return is_locked if verify == :handles_are_cleared
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
        if @file_handle # Only for Windows
          @file_handle.close
          @file_handle = nil
          is_locked = true
        else # Doesn't return status properly for non-windows, just resets the lock
          if ($oats_execution.nil? or $oats_execution['agent'].nil?) and RUBY_PLATFORM !~ /(mswin|mingw)/ and File.exist?(lock_file)
            pids = IO.readlines(lock_file)
            current_pid = pids.shift
            pids.each { |pid| Util.kill(pid.chomp) } # Legacy firefox
          end
          is_locked = false
        end
        FileUtils.rm_f lock_file
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