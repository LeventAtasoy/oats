#require 'util'
class OatsOsshMissingInput < OatsTestError ; end

module Oats

  # Implement Oats.rssh and Oats.rput functionality. See Oats.rssh documentation.
  module Ossh
    def Ossh.run(cmd_file, dir = nil ,  host = nil, username = nil, rput = nil)
      username ||= Oats.data['ssh']['username']
      host ||= Oats.data['ssh']['host']
      raise(OatsOsshMissingInput, "Ossh plink requires a host.") unless host
      if username == 'root'
        cmd = "plink #{host} -l #{Oats.data['ssh']['root_sudo_username']} "
        cmd_file = 'sudo -u root ' + cmd_file
      else
        cmd = "plink #{host} -l #{username} "
      end
      if rput
        source_cmd = 'echo'
        if File.exist?(cmd_file)
          cmd_file.gsub! /\//, '\\'
          source_cmd = 'type'
        end
        cmd = "#{source_cmd} #{cmd_file} | #{cmd}\"/home/levent.atasoy/bin/oats_put_file.sh #{dir}\""
      else
        if dir
          cmd += "\"cd #{dir} ; #{cmd_file} 2>&1\""
        else
          cmd += "\"#{cmd_file} 2>&1\""
        end
      end
      $log.info cmd
      `#{cmd}`
    end
  end
end
