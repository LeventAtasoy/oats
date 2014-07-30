# Manages a lock file indicating a OATS session is in process
require 'rbconfig'
require 'win32ole' if RbConfig::CONFIG['host_os'] =~ /mswin|msys|mingw|cygwin|bccwin|wince|emc/
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
        if Oats.os != :windows or ENV['TEMP'] =~ /^\/cygdrive/
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
      if Oats.os != :windows or ENV['TEMP'] =~ /^\/cygdrive/
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
            pids.each { |pid| Util.kill(pid.chomp) }
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

    # Removes lock
    def OatsLock.reset
      if @@file_handle  # Only for Windows
        @@file_handle.close
        @@file_handle = nil
        @@is_locked = true
      else # Doesn't return status properly for non-windows, just resets the lock
        if $oats_execution['agent'].nil? and Oats.os != :windows and File.exist?(in_progress_file)
          pids = IO.readlines(in_progress_file)
          current_pid = pids.shift
          pids.each { |pid| Util.kill(pid.chomp) } # Legacy firefox
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
        return ENV['OATS_USER_HOME'] + '/' + lock_file
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