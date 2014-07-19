require 'oats/oats_selenium_api'

# Advertised OATS methods to be used from tests
# Selenium object accessor created on demand by Oat.browser

def selenium
  $selenium || Oats.browser
end

module Oats

  class Oselenium
    @@browsers = []
    attr_reader :browser, :site, :login_base_url, :user
    @@server_started_by_oats = false

    def Oselenium.browsers
      @@browsers
    end

    def Oselenium.browser(*args)
      if args.include?(true)
        new_browser = true
        args.delete true
      end
      if not args.empty?
        if not new_browser and Oselenium.browsers.last
          return Oselenium.browsers.last.login(*args)
        else
          return Oselenium.new(*args).browser
        end
      elsif Oselenium.browsers.last
        return Oselenium.browsers.last
      else
        return Oselenium.new.browser
      end
    end

    def initialize(*args)

      browser_type = $oats['selenium']['browser_type']
      #    is_webdriver = ! $oats['selenium']['rcdriver']

      unless $oats_global['download_dir']
        if browser_type == 'firefox'
          $oats_global['download_dir'] = $oats['execution']['dir_results'] + '/downloads'
        elsif Oats.data("selenium.default_downloads")
          $oats_global['download_dir'] = File.join(ENV[ RUBY_PLATFORM =~ /(mswin|mingw)/ ? 'USERPROFILE' : 'HOME'], 'Downloads')
          $oats_global['download_dir'].gsub!('\\','/') if RUBY_PLATFORM =~ /(mswin|mingw)/
        end
      end

      download_dir = $oats_global['download_dir'].gsub('/','\\\\') if $oats_global['download_dir'] and
        RUBY_PLATFORM =~ /(mswin|mingw)/
      download_dir ||= $oats_global['download_dir']
      case browser_type
      when 'firefox'
        profile = $oats['selenium']['firefox_profile']
        $oats_global["browser_path"] ||= ENV[profile] if profile
        #      if is_webdriver
        profile = Selenium::WebDriver::Firefox::Profile.from_name profile if profile
        profile = Selenium::WebDriver::Firefox::Profile.new unless profile
        profile['browser.download.dir'] = download_dir
        profile["browser.helperApps.neverAsk.saveToDisk"] = "text/plain, application/vnd.ms-excel, application/pdf, text/csv"
        profile['browser.download.folderList'] = 2
        $oats['selenium']['firefox_profile_set'].each { |method,value| profile.send method+'=', value }

      when 'chrome'
        profile = Selenium::WebDriver::Chrome::Profile.new
        profile['download.prompt_for_download'] = false
        profile['download.default_directory'] = download_dir
#        unless $oats_global['browser_path']
#          vpath = File.join($oats['_']['vendor'], ENV['OS'], 'chromedriver' + (RUBY_PLATFORM =~ /(mswin|mingw)/ ? '.exe' : '') )
#          $oats_global['browser_path'] = vpath if File.exist?(vpath)
#        end
      end
      FileUtils.rm_f Dir.glob(File.join($oats_global['download_dir'],'*')) if $oats_global['download_dir']
      Oats.info "Browser type: #{browser_type.inspect}, profile: #{profile.inspect}, path: #{$oats_global["browser_path"].inspect}"
      $oats_info['browser'] = $oats['selenium']['browser_type'].sub(/ .*/,'')
      remote_webdriver = $oats['selenium']['remote_webdriver']
      driver_type = $oats['selenium']['browser_type']
      if remote_webdriver
        remote_webdriver = remote_webdriver[browser_type]
        if remote_webdriver
          driver_type = 'remote'
          @remote_webdriver_is_active = true
        end
      end
      opts = [ driver_type.to_sym ]
      opts_hash ={}
      opts_hash[:profile] = profile if profile and driver_type != 'remote'
      if driver_type == 'remote'
        opts_hash[:url] = "http://"+remote_webdriver+'/wd/hub'
        opts_hash[:desired_capabilities] = $oats['selenium']['browser_type'].to_sym
      end
      case browser_type
      when /firefox/
        Selenium::WebDriver::Firefox.path = $oats_global["browser_path"]
      when /chrome/
        Selenium::WebDriver::Chrome.driver_path = $oats_global['browser_path']
      end if $oats_global['browser_path']
      browser_options = Oats.data "selenium.options.#{browser_type}"
      browser_options.each_pair { |name, val| opts_hash[name.to_sym] = val } if browser_options
      opts.push(opts_hash) unless opts_hash.empty?
      #      OatsLock.record_firefox_processes do
      @browser = Selenium::WebDriver.for(*opts)
      #      end
      @browser.osel = self
      $selenium = @browser
      @@browsers << @browser
      login(*args)
    end

    # Stub method/interface for actions to take after instantiating the browser
    def login(*args) #
      selenium.open(args.first)
    end

    # True if selenium is running in remote_webdriver mode
    def remote_webdriver?
      @remote_webdriver_is_active
    end

    # Fixes the path to Windows if running on windows remote webdriver
    def Oselenium.remote_webdriver_map_file_path(file)
      if $selenium and $selenium.osel.remote_webdriver?
        file.sub!(ENV['OATS_DIR'], $oats['selenium']['remote_webdriver']['oats_dir'])
        file_os = $oats['selenium']['remote_webdriver']['os']
      else
        file_os = RUBY_PLATFORM
      end
      file_os =~ /(mswin|mingw)/ ? file.gsub('/','\\') : file
    end

    def Oselenium.reset
      Oselenium.close
    rescue Timeout::Error
      ## Sometimes doesn't die gracefully. It is OK, will be killed below.
    ensure
      @@browsers = []
      $selenium = nil
      OatsLock.kill_webdriver_browsers
    end

    def Oselenium.close
      while browser = Oselenium.browsers.pop
        if browser.osel.site
          browser.oats_debug "Closing browser session from #{browser.osel.site}"
        else
          browser.oats_debug "Closing browser session."
        end
        browser.quit
      end
      $selenium = nil
    end

    def Oselenium.pause_browser
      return if Oselenium.browsers.empty? or ! TestData.pause_after_error
      seconds = 999999
      pause_val = $oats['selenium']['pause_on_exit']
      if not pause_val.integer? or
          pause_val <= 0
        seconds = nil
      elsif pause_val == 1
        seconds = nil unless TestData.current_test.status == 1
      elsif pause_val > 0
        seconds = pause_val
      end
      if seconds
        $stderr.puts "Paused because selenium:pause_on_exit is set to [#{pause_val}]"
        $stderr.puts "PLEASE HIT <ENTER> TO CONTINUE!"
        begin
          # timeout(seconds) { loop { browser.get_title ; sleep 1 } }
          timeout(seconds) { STDIN.readline }
        rescue Timeout::Error
        end
      end
      TestData.pause_after_error = false
    end

    def Oselenium.port
      #    if $oats_execution['agent']
      #      '4'+$oats_execution['agent']['execution:occ:agent_port'].to_s
      #    else
      $oats['selenium']['port']
      #    end
    end
  end
end
