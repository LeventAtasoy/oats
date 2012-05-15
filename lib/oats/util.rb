require 'win32/process' if RUBY_PLATFORM =~ /(mswin|mingw)/ and not defined?(Process)

module Oats
  module Util

    #  def Util.cygwin_fix_path(file,dir = nil)
    #  end
    def Util.expand_path(file,dir = nil)
      file = File.expand_path(file, dir)
      file.sub!('/',':/') if file.sub!('/cygdrive/','')
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
            base = path.sub(/#{extn}\z/,'')
            base.sub!(/(_\d*)?\z/,"_#{cnt}")
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
    def Util.clear_port(port,log)
      matching_busy_port_line = IO.popen('netstat -a -o').readlines.grep(Regexp.new(port.to_s)).first
      return unless matching_busy_port_line and matching_busy_port_line =~ /LISTENING/
      pid = matching_busy_port_line.chomp!.sub(/.*LISTENING *(\d+).*/,'\1')
      log.warn "Likely busy port: [#{matching_busy_port_line}]"
      # Cygwin specific code
      #    pid_line = IO.popen("pslist #{pid}").readlines.grep(Regexp.new('java.*'+pid.to_s)).first
      #    log.warn pid_line
      #    begin
      log.warn "Will attempt to kill the PID #{pid}"
      signal = 'KILL'
      killed = Process.kill(signal,pid.to_i)
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
    def Util.clear_handle(hstring,*proc_names)
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
      killed = Process.kill(signal,pid.to_i)
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
