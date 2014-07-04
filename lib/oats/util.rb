require 'win32/process' if RUBY_PLATFORM =~ /(mswin|mingw)/ and not defined?(Process)

module Oats
  module Util

    # Kills processes matching the given Regexp
    # @example kill(/firefox/) # will kill all processes containing word 'firefox'
    # @param  One of [Regexp] proc_names, [String] pid, or array from find_matching_processes
    # @param [String] info_line to output
    # @return [Array] pids of killed processes
    def self.kill(process_selector, info_line=nil)
      case process_selector
        when Array
          procs = process_selector
        when String
          procs = [pid, process_selector, nil]
        when Regexp
          procs = self.find_matching_processes(process_selector)
      end
      signal = 'KILL'
      killed_procs = []
      procs.each do |pid, proc_name, ppid|
        info_line ||= "#{pid} " + proc_name
        process_exists = true
        begin
          killed = Process.kill(signal, pid.to_i)
        rescue Errno::ESRCH # OK if the process is gone
          process_exists = false
        end
        if process_exists
          if killed == 0
            Oats.warn "Failed to kill [#{info_line||pid}]"
          else
            Oats.warn "Successfully killed [#{info_line||pid}]"
            killed_procs.push pid
          end
        end
      end
      killed_procs
    end

    # Returns pid array of matching processes
    # @example find_matching_processes(/firefox/) # will return all processes containing word 'firefox'
    # @param [Regexp] proc_names to match existing processes
    def self.find_matching_processes(proc_names)
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
          #          puts [process.Commandline, process.ProcessId, process.name].inspect
          if process.Commandline =~ proc_names
            matched.push [process.ProcessId, process.Name, nil, process.CommandLine]
          end
        end
      else
        pscom = RUBY_PLATFORM =~ /linux/ ? 'ps lxww' : 'ps -ef'
        `#{pscom}`.split("\n").each do |lvar|
          line = lvar.chomp
          case RUBY_PLATFORM
            when /darwin/ #  ps -ef output
              if line =~ /\s*\d*\s*(\d*)\s*(\d*)\s*\d\s*\S*\s\S*\s*\S*\s(.*)/
                pid = $1
                ppid = $2
                proc_name = $3
              end
            when /linux/ #  ps ww output
              pid = line[7..12]
              next if pid.to_i == 0
              ppid = line[13..18]
              proc_name = line[69..-1]
            else
              raise OatError, "Do not know how to parse ps output from #{RUBY_PLATFORM}"
          end
          next unless pid
          if proc_name =~ proc_names
            matched.push [pid.strip, proc_name.strip, ppid.strip, line.strip]
          end
        end
      end
      return matched
    end

    # Same as File.expand_path, but handles /cygdrive/
    def self.expand_path(file, dir = nil)
      file = File.expand_path(file, dir)
      file.sub!('/', ':/') if file.sub!('/cygdrive/', '')
      file
    end

    # Returns a unique path in dir using basename of file_name.
    # file_name:: Appends '_count' to the the basename if the file already exists.
    # dir:: if not given, uses the dirname of file_name. If file_name does not
    #       have dirname, assumes dir = '.'  If dir does not exist, it is created.
    def Util.file_unique(file_name, dir = nil)
      new_path, existing_path = Util.file_examine(file_name, dir)
      return new_path
    end

    # Returns the file path for the existing file with the highest _count in dir
    # dir:: if not given, uses the dirname of file_name. If file_name does not
    #       have dirname, assumes dir = '.'  If dir does not exist, it is created.
    def Util.file_latest(file_name, dir = nil)
      new_path, existing_path = Util.file_examine(file_name, dir)
      return existing_path
    end

    # Returns a unique path in dir using basename of file_name for a new file
    # and also return the file path for the existing file with the highest _count
    # in dir.
    # file_name:: Appends '_count' to the the basename if the file already exists.
    # dir:: if not given, uses the dirname of file_name. If file_name does not
    #       have dirname, assumes dir = '.'  If dir does not exist, it is created.
    def Util.file_examine(file_name, dir = nil)
      fname = File.basename(file_name)
      dir ||= File.dirname(file_name)
      dir = '.' unless dir
      existing_path = nil
      path = File.join dir, fname
      if File.directory?(dir)
        (1..100).each do |cnt|
          break unless File.exist?(path)
          existing_path = path
          extn = File.extname(path)
          if extn
            base = path.sub(/#{extn}\z/, '')
            base.sub!(/(_\d*)?\z/, "_#{cnt}")
            path = base + extn
          else
            path = File.join dir, file_name + "_#{cnt}"
          end
        end
      else
        FileUtils.mkdir_p(dir)
      end
      existing_path = Util.expand_path(existing_path) unless existing_path.nil?
      return Util.expand_path(path), existing_path
    end

    # Kill process occupying a port
    def Util.clear_port(port, log)
      matching_busy_port_line = IO.popen('netstat -a -o').readlines.grep(Regexp.new(port.to_s)).first
      return unless matching_busy_port_line and matching_busy_port_line =~ /LISTENING/
      pid = matching_busy_port_line.chomp!.sub(/.*LISTENING *(\d+).*/, '\1')
      log.warn "Likely busy port: [#{matching_busy_port_line}]"
      # Cygwin specific code
      #    pid_line = IO.popen("pslist #{pid}").readlines.grep(Regexp.new('java.*'+pid.to_s)).first
      #    log.warn pid_line
      #    begin
      log.warn "Will attempt to kill the PID #{pid}"
      signal = 'KILL'
      killed = Process.kill(signal, pid.to_i)
      if killed.empty?
        log.warn "Failed to kill the process"
        return false
      else
        log.warn "Successfully killed the process."
        return true
      end
    end

    # Kill process using a handle
    # Util.clear_handle('oats_in_progress.lock','java','ruby') willl kill
    def Util.clear_handle(hstring, *proc_names)
      pid = nil
      proc_name = nil
      handle_string = nil
      line = nil
      matches = IO.popen("handle #{hstring}").readlines
      matches.each do |lvar|
        line = lvar
        line =~ /(.*) pid:(.*) .*: (.*)/
        next unless $1
        proc_name = $1.strip
        pid = $2.strip
        handle_string = $3.strip
        if handle_string =~ /#{hstring}/
          proc_names.each do |name|
            break if proc_name =~ /#{name}/
          end
        end
      end
      return unless pid
      puts "Likely locking process: [#{line}]"
      # Cygwin specific code
      #    pid_line = IO.popen("pslist #{pid}").readlines.grep(Regexp.new('java.*'+pid.to_s)).first
      #    log.warn pid_line
      #    begin
      puts "Will attempt to kill the PID #{pid}"
      signal = 'KILL'
      killed = Process.kill(signal, pid.to_i)
      if killed.empty?
        puts "Failed to kill the process"
        return false
      else
        puts "Successfully killed the process."
        return true
      end
    end

  end
end
