require 'watir-webdriver'
module Oats
  module Selenium
    @@browser = nil # pointer to current browser

    # Returns Oats.data 'selenium.browser_type'
    def self.browser_type
      Oats.data('selenium.browser_type')
    end

    # Returns existing browser or creates a new one
    # Parameters
    #  :is_existing:: [True] Returns existing browser or nil
    #            [False] Default, creates one if it does not exist
    #  self.browser(is_existing:true) # Will return existing browser or nil.
    def self.browser(is_existing=nil, opt = {})
      is_existing ||= opt[:is_existing]
      return @@browser if is_existing or @@browser
      browser_type = Oats.data('selenium.browser_type').to_sym
      case browser_type
        when :firefox
          profile = $oats['selenium']['firefox_profile']
          $oats_global["Selenium::browser_path"] ||= ENV[profile] if profile
          profile = ::Selenium::WebDriver::Firefox::Profile.from_name profile if profile
          profile = ::Selenium::WebDriver::Firefox::Profile.new unless profile # if profile above not created
          profile['browser.download.dir'] = download_dir
          profile["browser.helperApps.neverAsk.saveToDisk"] = "text/plain, application/vnd.ms-excel, application/zip, application/pdf, text/csv, application/octet-stream"
          profile['browser.download.folderList'] = 2
          $oats['selenium']['firefox_profile_set'].each { |method, value| profile.send method+'=', value }
          Selenium::WebDriver::Firefox.path = $oats_global['Selenium::browser_path'] if $oats_global['Selenium::browser_path']
          opts ||= {:profile => profile}
        when :chrome
          # if Oats.data('selenium.webdriver')
          opts = {:prefs => {:download => {
              :prompt_for_download => false,
              :default_directory => "/path/to/dir"}}}
          # else
          #   profile = ::Selenium::WebDriver::Chrome::Profile.new
          #   profile['download.prompt_for_download'] = false
          #   profile['download.default_directory'] = self.download_dir
          #   opts = {:switches => %w[--test-type], :profile => profile}
          opts[:switches] = %w[--test-type] # Eliminates the -- certificate... warning
        #   opts = {:profile => profile}
        # end
        #Selenium::WebDriver::Chrome.driver_path = $oats_global['Selenium::browser_path'] if $oats_global['Selenium::browser_path']
        # caps = Selenium::WebDriver::Remote::Capabilities.chrome("chromeOptions" => {"args" => [ "--test-type" ]})
        #driver = Selenium::WebDriver.for :remote, url: 'http://localhost:4444/wd/hub' desired_capabilities: caps
        when :safari
          opts = {:profile => nil}
      end
      # Use 32 bit IEDriverServer, config security as documented.
      args = (browser_type == :ie or opts.nil?) ? [browser_type] : [browser_type, opts]
      Oats.info "Browser type: #{browser_type.inspect}, profile: #{profile.inspect}, path: #{$oats_global["browser_path"].inspect}"
      @@browser =
          if Oats.data('selenium.webdriver')
            Selenium::WebDriver.for *args
          else
            Watir::Browser.new *args
          end
      Oats.debug "Created browser: #{@@browser.to_s}"
      # @@browser.window.maximize if browser_type == :chrome  # On Mac Mini
      @@browser
    end

    # Capture system screenshot and logs3
    # Parameters:
    #  :name:: [String]  of captured file if successful, or nil.
    def self.system_capture
      # return if $selenium.nil? or # Snapshots are not supported on Ubuntu/Chrome
      #     ($oats['selenium']['browser_type'] == 'chrome' and Oats.os == :linux)
      browser = Selenium.browser(true)
      return nil unless browser
      ct = TestData.current_test
      file = Util.file_unique(fn="selenium_screenshot.png", ct.result)
      Oats.info "Will attempt to capture webpage: #{file}"
      begin
        timeout(Oats.data('selenium.capture_timeout')||15) { browser.screenshot.save(file) }
        ct.error_capture_file = file
      rescue ::Selenium::WebDriver::Error::NoSuchWindowError => e
        Oats.warn "Could not capture page. Resetting browser, due to: #{e}"
        self.reset
      rescue => e
        Oats.warn "Could not capture page screenshot due to: #{e}"
      end
      if File.zero?(file)
        Oats.info "Removing selenium_screenshot.pgn file since it is empty."
        File.delete(file)
        file = nil
      end
      return file
    end



    def self.close
      br = self.browser(true)
      return unless br
      Oats.debug "Closing the browser: #{br.to_s}"
      @@browser = nil # Do this first, in case close bombs
      br.close
    end

    def self.reset
      timeout = 30
      # Oats.debug "Resetting Selenium Browser..."
      Timeout::timeout(timeout) { self.close }
    rescue Timeout::Error
      Oats.debug "#{self.class} close took longer than #{timeout} seconds ..."
    ensure ## Browsers sometimes doesn't die gracefully. In that case, they will be killed below.
      @@browser = nil
      Oats::Util.kill(/IEDriverServer|IEXPLORE.EXE\" -noframemerging|\/safaridriver-|chromedriver|chrome\.exe\" .* --enable-logging |firefox(-bin|\.exe\") -no-remote/) #if Oats.os == :darwin
    end

    def self.download_dir
      return $oats_global['Selenium::download_dir'] if $oats_global['Selenium::download_dir']
      $oats_global['Selenium::download_dir'] = File.join(ENV[Oats.os == :windows ? 'USERPROFILE' : 'HOME'], 'Downloads')
      $oats_global['Selenium::download_dir'].gsub!('\\', '/') if Oats.os == :windows # Selenium::WebDriver::Platform.windows?
      FileUtils.mkpath($oats_global['Selenium::download_dir'])
      return $oats_global['Selenium::download_dir']
    end

    def self.mark_downloaded
      FileUtils.touch(File.join(self.download_dir, 'SeleniumDownload.flag')).first
    end

    # Moves files downloaded by selenium into the current Oats.test.result directory.
    # Assumes downloaded file is not empty
    # Returns [Array] basenames of copied files.
    # Parameters:
    #   :file_glob_name:: [String] to be collected. Uses shell notation, defaulting to '*'.
    #   :marker:: [Hash] file created via mark_downloaded, collect only files created after marker
    def self.collect_downloaded(*args)
      param = args.last.instance_of?(Hash) ? args.pop : {}
      file_glob_name = '*'
      #    cur_test.collect_downloaded_output if cur_test && cur_test.instance_of?(TestCase)
      marker_file = param[:marker] if param and param[:marker]
      download_dir = self.download_dir
      case Oats.data('selenium.browser_type')
        when 'firefox'
          downloading_extension = '.part'
        when 'safari'
          downloading_extension = '.download'
          marker_file ||= File.join(download_dir, 'SeleniumDownload.flag')
      end
      downloaded_files = []
      files = []
      Oats.wait_until("There were no files in: #{download_dir}") do
        begin
          files = Dir.glob(File.join(download_dir, file_glob_name))
          if marker_file
            sorted = files.sort_by do |file|
              t1 = File.ctime(file)
            end
            id = sorted.index(marker_file)
            files = sorted[id+1..-1]
          end
        end while files.empty? and downloaded_files.empty? and sleep(1)
        files.each do |e|
          # Ensure file is fully downloaded
          old_size = 0
          Oats.wait_until do
            ext = File.extname(e)
            if ext == downloading_extension
              !File.exist?(e)
            else
              new_size = File.size?(e) # Returns nil if size is zero. Assumes downloaded file is not empty
              if new_size and new_size == old_size # File size stabilized
                FileUtils.mv(e, '.')
                downloaded_files.push(File.basename(e))
              else
                old_size = new_size
                false
              end
            end
          end
        end
        files.empty? # Look once more for files
      end
      return downloaded_files
    end

    # Obsolete, move code to self.reset as tested for windows & chrome . Below used to be in Oats::Util
    def kill_webdriver_browsers

      # Kill all selenium automation chrome jobs on MacOS. Assumes MacOS is for development only, not OCC.
      # Will cause problems if multiple agents are run on MacOS

      #      match = "ruby.*oats/lib/oats_main.rb"
      match = 'ruby.*oats(\\\\|\/)bin(\\\\|\/)oats'
      # Not tested on agents on Windows_NT
      if $oats_execution['agent']
        nickname = $oats_execution['agent']['execution:occ:agent_nickname']
        port = $oats_execution['agent']['execution:occ:agent_port']
        match += " -p #{port} -n #{nickname}"
      end

      oats_procs = self.find_matching_processes(/#{match}\z/)
      chromedriver_procs = self.find_matching_processes(/IEXPLORE.EXE\" -noframemerging|(chromedriver|firefox(-bin|\.exe\") -no-remote)/)
      webdriver_procs = self.find_matching_processes(/webdriver/)
      oats_procs.each do |opid, oproc_name, oppid|
        chromedriver_procs.each do |cpid, cproc_name, cppid|
          if cppid == opid
            webdriver_procs.each do |wpid, wproc_name, wppid|
              self.kill_pid wpid if wppid == cpid
            end
            self.kill_pid cpid
          end
        end
      end
      # If parent ruby dies, ppid reverts to "1"
      (chromedriver_procs + webdriver_procs).each do |pid, proc_name, ppid|
        if Oats.os == :windows
          self.kill_pid pid
        else
          self.kill_pid pid if ppid == "1" and proc_name !~ /defunct/
        end
      end
    end

  end
end
