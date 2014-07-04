# IDE Class to run an IDE based HTML suite after transforming it based on oats_data

module Oats

  # Runs an IDE based HTML suite after transforming it based on current Oats data
  class Ide
    def initialize()
      super
      @suite_base_url_signin_type = nil;
      @first_test_url = nil;
    end

    # Run input_suite_path while in a TestData.dir . Assumes Oats.data is initialized for TestData.dir
    # input_suite_path:: path to the suite HTML
    # hash:: list from => to values to use for regeneration of the included test cases.
    def run (input_suite_path, hash = nil )
      begin
        run_ide(input_suite_path, hash)
      ensure
        TestData.current_test.collect_downloaded_output
      end
    end

    private

    def run_ide (input_suite_path, hash = nil )
      suite_path = get_path(input_suite_path)
      name = File.basename(suite_path)
      doc = open(suite_path ) { |f| Hpricot(f) }
      #    FileUtils.rm Dir[File.join(TestData.current_test.dir,'*.gen.*')] # Clean previously generated files
      FileUtils.rm Dir['*.gen.*'] # Clean previously generated files in pwd
      if doc.search("head[@profile='http://selenium-ide.openqa.org/profiles/test-case']").empty?
        regen_suite = nil
        doc.search('a[@href]') do |a|
          if Oats.data['execution']['run_in_dir_results']
            generated_test = regenerate_html(a['href'], test.result, File.dirname(suite_path), hash)
          else
            generated_test = regenerate_html(a['href'], test.dir, File.dirname(suite_path), hash)
          end
          if generated_test
            regen_suite = true
            a.set_attribute(:href,generated_test)
          end
        end
        html_suite_path =  File.join(test.dir , File.basename(suite_path,'.*') + '.gen.html')
        regen_suite = true if regen_suite or html_suite_path != suite_path
        html_suite_path =  File.join(test.result , File.basename(suite_path,'.*') + '.gen.html') if Oats.data['execution']['run_in_dir_results']
        $log.info "Creating: #{html_suite_path}"
        File.open( html_suite_path, 'w' ) { |out| out.print doc } if regen_suite
      else # A single test HTML, not the suite
        raise OatsTestError, "Input file is not an IDE suite: " + html_suite_path
      end

      # Execute html_suite_path
      result_file = File.join(test.result, File.basename(name, '.*') + '_results.html')
      if Oats.data['selenium']['ide']['generate']
        $log.warn "Option execution:ide:generate is set. Test will not be executed."
        $log.debug "Target result_file was: #{result_file}"
        return
      end
      rc_jar_file = File.join(Oats.data['_']['vendor'],'selenium-server.jar')
      browser = '*' + Oats.data['selenium']['browser_type'].sub(/ .*/,'')
      url = nil
      if @suite_base_url_signin_type
        url = Oats.data[@suite_base_url_signin_type]["SignIn"]["url"]
      else
        if @first_test_url
          url = @first_test_url
        else
          raise(OatsError, "None of the tests in #{suite_path} specified a base URL.")
        end
      end
      if url
        base_url = url.match('https?://[^/]*/?')
      else
        base_url = nil
      end
      port = Oats.data['selenium']['ide']['port']
      if Oats.data['env.web.host']
        base_url = 'http://' + Oats.data['env.web.host']
      else
        base_url = base_url[0]
      end
      #    if base_url
      #      base_url = base_url[0]
      #    else
      #      base_url = 'http://' + Oats.data['env']['web']['host']
      #      $log.warn "Can not determine the base url from [#{url}]. Assuming base url is [#{base_url}]" \
      #        unless @suite_base_url_signin_type and Oats.data[@suite_base_url_signin_type]["SignIn"]
      #    end
      command = "java -jar \"#{rc_jar_file}\" -port #{port}"
      command +=  " -timeout #{Oats.data['selenium']['ide']['suite_timeout']}" if Oats.data['selenium']['ide']['suite_timeout']
      # Don't use profiles when using RC in IDE mode
      command += " -firefoxprofileTemplate \"#{$oats_global['firefox_profile_dir']}\"" \
        if Oats.data['selenium']['browser_type'] =~ /firefox/ and $oats_global['firefox_profile_dir']
      command += " -htmlSuite #{browser} #{base_url} \"#{html_suite_path}\" \"#{result_file}\" 2>&1"
      $log.info "Starting Selenium Remote Control: #{command}"
      #    return  # DEBUG
      first_rc_try = true
      failure_line = nil
      catch :end_rc do
        2.times do
          IO.popen(command) do |io|
            while io.gets do
              $log.info chomp
              if /Selenium is already running on port/ =~ $_
                if first_rc_try
                  io.readlines.each {|line|$log.info line.chomp }
                  Util.clear_port(Oats.data['selenium']['ide']['port'],$log)
                  $log.info "Will attempt to restart Selenium RC..."
                else
                  #                raise(OatsError, $_, caller[1..3])
                  raise(OatsError, $_)
                  throw(:end_rc)
                end
                first_rc_try = false
              elsif /fail/i =~ $_ and /Failed to start: SocketListener/ !~ $_
                failure_line = $_
                throw(:end_rc)
              elsif /exception/i =~ $_ # Like server.SeleniumCommandTimedOutException
                failure_line = $_
              end
            end
          end
          throw(:end_rc) if first_rc_try
        end
      end
      #    pause_val = Oats.data['execution']['ide']['pause_on_exit']
      seconds = 999999
      pause_val = $oats['selenium']['pause_on_exit']
      if not pause_val.integer? or
          pause_val <= 0
        seconds = nil
      elsif pause_val == 1
        seconds = nil unless failure_line
      elsif pause_val > 0
        seconds = pause_val
      end
      raise(OatsError, "Result file is not readable: #{result_file}") unless File.readable?(result_file)
      if seconds
        # Need to quote browser path for cygwin because it may have spaces.
        begin
          timeout(seconds) do
            #  $stderr.puts "Paused because selenium:pause_on_exit is set to [#{pause_val}]"
            #  $stderr.puts "PLEASE HIT <ENTER> TO CONTINUE!"
            successful = system( '"' +Oats.data['selenium']['ide']['result_browser'] + '" file://'+result_file)
            $log.error "Error trying to open results file: #{$?}" \
              unless successful or $? == 256
          end
        rescue Timeout::Error
        end
      end
      TestData.pause_after_error = false
      $log.info "Results are at: file://#{result_file}"
      raise(OatsTestError, failure_line) if failure_line
    end

    # Helper method to replace HTML file contents based on oats and test data mappings.
    def map_file_contents(oats_data, test_data, file_contents,key_path)
      return unless test_data
      #    $log.debug key_path
      if @suite_base_url_signin_type.nil?
        @suite_base_url_signin_type = 'Campaign' if key_path == 'root:Campaign:SignIn'
        @suite_base_url_signin_type = 'Admin' if key_path == 'root:Admin:SignIn'
        #      $log.debug "Base URL is set to #{baseUrl}"
      end
      test_data.each do |key,val|
        repVal = oats_data[key]
        next if val.nil? or repVal.nil?
        if val.class == Hash
          map_file_contents( repVal, val, file_contents,key_path + ':' + key)
        else
          file_contents.gsub!(val, repVal.to_s)
          test_data[key] = repVal
        end
      end
    end

    # Updates HTML file contents based on current oats_data into test_dir_out
    # Returns generated file name or nil if no new file is generated
    def regenerate_html(file_in, dir_out, dir_in = dir_out, hash = nil)
      basename = File.basename(file_in,'.*')
      file_in_absolute = File.expand_path(file_in,dir_in) # get absolute path
      unless File.exist?(file_in_absolute)
        file_in_absolute = Dir.glob( File.join( $oats['execution']['dir_tests'],
            '/**/', file_in.sub(/^(\.\.\/)*/, ''))).first
        #        file_in = file_in.sub!(/[^\/]*\//,'')
        raise(OatsError,"Can not locate IDE test case file: [#{file_in}]") unless file_in_absolute
      end
      file_in_root = file_in_absolute.sub(/(.*)\..*$/,'\1')
      yaml_in = file_in_root + '.yml'
      file_out_root = File.join(dir_out, basename)
      file_gen = file_out_root +'.gen.html'
      yml_out = file_out_root +'.gen.yml'
      new_base_name = basename
      if File.exist?(file_gen)
        new_base_name = File.basename(File.dirname(file_in)) + '_' + new_base_name
        file_gen = File.join(dir_out, new_base_name ) +'.gen.html'
        yml_out =  File.join(dir_out, new_base_name ) +'.gen.yml'
      end
      if @suite_base_url_signin_type.nil? and @first_test_url.nil?
        doc = open(file_in_absolute) { |f| Hpricot(f) }
        link = doc.at("link[@rel='selenium.base']")
        @first_test_url = link['href'] unless link.nil?
      end
      unless File.exist?(yaml_in)
        return nil if file_in_root == file_out_root
        $log.info "Copying [#{file_in_absolute}] to: #{file_gen}]"
        FileUtils.cp(file_in_absolute, file_gen)
        return basename + '.gen.html'
      end
      $log.debug "Regenerating [#{file_in_absolute}] into [#{file_gen}] based on [#{yaml_in}]"
      file_contents = IO.read(file_in_absolute)
      test_data = YAML.load_file(yaml_in)
      map_file_contents(Oats.data, test_data, file_contents, 'root')
      hash.each { |val, rep_val| file_contents.gsub!(val, rep_val) } if hash
      if Oats.data['selenium']['browser_type'] =~ /iexplore/
        file_contents.sub!(/(<\/IE-ONLY>.*-->)/,'<-- \1')
        file_contents.sub!(/(<!--.*<IE-ONLY>)/,'\1 -->')
      end
      File.open( file_gen, 'w' ) { |out| out.print file_contents }
      File.open( yml_out, 'w' ) { |out| YAML.dump( test_data, out ) }
      basename + '.gen.html'
    end

  end
end
