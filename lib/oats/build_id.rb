# To change this template, choose Tools | Templates
# and open the template in the editor.

module Oats

  module BuildId
    def BuildId.generate
      dir_results = $oats['execution']['dir_results']
      env_name = $oats['env']['name']
      return unless env_name and $oats['execution']['build_version']
      TestList.current.variations.last.env_name = env_name
      run_info_file = File.join(dir_results,'run_info_' + env_name + '.txt')
      unless File.exist?(run_info_file)
        File.open(run_info_file, 'w') do |f|
          YAML.dump($oats,f)
        end
      end
      if Oats.context['build_version'] # Collected build data previously
        return if Oats.context['build_version']['execution'] == $oats['execution']['build_version'] # no change
        Oats.context['build_version']['execution'] = $oats['execution']['build_version'] # Use the latest, input from test list
        return
      end
      # First time collecting build data
      Oats.context['build_version'] = { 'execution' => $oats['execution']['build_version'] }
      all_build_info = ''
      build_id_file = File.join(dir_results,'buildID_' + env_name + '.txt')

      for host in $oats['execution']['build_versions'] do
        web_host = $oats['env'][host] && $oats['env'][host]['host']
        next unless web_host
        urls = $oats['env'][host]['buildID_url']
        next unless urls
        urls = [ urls ] unless urls.instance_of? Array
        versions = ''
        urls.each do |url|
          begin
            if RUBY_VERSION =~ /^1.9/
              resp = Net::HTTP.new(web_host, 80).get(url) # 1.9 doesn't like the second parameter
            else
              resp = Net::HTTP.new(web_host, 80).get(url, nil )
            end
            build_info = resp.body if resp.code == '200'
          rescue
            $log.error $!.to_s
            $log.error "Occurred after issuing get request to [http://#{web_host}#{url}]"
            build_info = nil
          end
          if build_info
            versions += ' ' unless versions == ''
            versions += build_info[6..(build_info.index("\n")-1)]
            all_build_info += "--- #{host} #{url} --- \n" + build_info + "\n"
          end
        end
        Oats.context['build_version'][host] = versions
      end if $oats['execution']['build_versions']
      File.open(build_id_file, 'w') { |f| f.puts all_build_info } unless all_build_info == ''
    end
  end
end
