require "selenium-webdriver"

#module Selenium
#  module WebDriver
#    class Driver
#      def bridge
#        @bridge
#      end
#    end
#  end
#end

class String
  def locator
    Oats::Locator.new(self)
  end
end

module Oats
  class Locator
    attr_accessor :element
    attr_reader :what, :ehow, :locator
    def initialize(locator, ehow=nil)
      if locator.instance_of?(Array)
        @ehow = locator[1]
        @what = locator[0]
      elsif locator.instance_of?(String)
        @what = @locator = locator
        if ehow
          @ehow = ehow
        else
          if locator[0,5] == 'link='
            @what = locator[5..-1]
            @ehow = :link
          elsif locator[0,5] == 'name='
            @what = locator[5..-1]
            @ehow = :name
          elsif locator[0,3] == 'id='
            @what = locator[3..-1]
            @ehow = :id
          elsif locator.index('/')
            @ehow = :xpath
          else
            @ehow = :name
          end
        end
      else
        raise('Unexpected arguments')
      end
    end

    def to_s
      @ehow.to_s + '='+ @what.to_s
    end

    include Comparable
    def <=>(locator)
      if locator.instance_of?(String)
        self.what <=> locator
      else
        if self.what == locator.what
          self.ehow <=> locator.ehow
        else
          self.what <=> locator.what
        end
      end
    end

    def ===(locator)
      self == locator
    end

    # Allow "link=Accounts".locator.wait.click
    def method_missing(id,*args)
      case id
      when :wait then id = :wait_for_element
      end
      #        if selenium.webdriver?
      @element ||= selenium.element?(self)
      if @element.respond_to?(id)
        @element.send(id, *args)
      else
        raise "#{@element} has no method #{id.inspect}"
      end
      #        else
      #          if selenium.respond_to?(id)
      #            selenium.send(id,self, *args)
      #          else
      #            raise "#{selenium} has no method #{id.inspect}"
      #          end
      #        end
    end
  end
end

class Selenium::WebDriver::Driver
  attr_accessor :osel, :no_oats_debug
  attr_reader :last_locator

  def webdriver?
    true
  end

  def logout
    osel.logout
    return self
  end

  def login(*args)
    osel.login(*args)
    return self
  end

  def alert(msg = nil, action = 'accept')
    return unless webdriver?
#    selenium.sleep 1
    alert = switch_to.alert;
    txt = alert.text
    if msg
      oats_debug "#{action}ing alert [#{txt}]"
      #        Oats.assert txt =~ /#{msg}/, "Alert text does not match input msg: [#{msg}]"
      Oats.assert(txt == msg, "Alert text does not match input msg: [#{msg}]")
    end
    alert.send(action);
  end

  # Makes an Oats.assert based on text? existence.
  def oats_assert_text(text_string)
    Oats.assert $selenium.text?(text_string), "Missing message: #{text_string}"
  end

  # Scrolls till element is visible.
  def scroll(locator)
    loc = element?(locator)
    loc.location_once_scrolled_into_view
  end

  def checked?(locator)
    oats_debug "checked? #{locator}"
    return is_checked_orig(locator) ? locator : false unless webdriver?
    loc = element?(locator)
    loc.element.selected? ? loc : false
  end
  alias :is_checked :checked?

  def click(locator)
    oats_debug "click #{locator}"
    #      if webdriver?
    el = element?(locator)
    Oats.assert el, "No element is found at locator #{locator}"
    el.click
    #      else
    #        click_orig(locator)
    #        el = locator
    #      end
    el
  end

  def ie?
    Oats.data('selenium.browser_type') =~ /ie/
  end

  def chrome?
    Oats.data('selenium.browser_type') =~ /chrome/
  end

  def firefox?
    Oats.data('selenium.browser_type') =~ /firefox/
  end

  # select
  def select(locator, value, noscript = nil, select_tag = 'option')
    oats_debug "select #{value} at #{locator} by tag_name #{select_tag}"
    #      unless webdriver?
    #        select_orig(locator, value)
    #        return locator
    #      end
    attribute, val = value.split(/=/)
    options = []
    if val
      attribute = 'text' if attribute == 'label'
    else
      val = attribute
      attribute = 'text'
    end
    if val.index("*")
      regex = true
    end
    el = element?(locator)
    if el
      el.find_elements(:tag_name,select_tag).each do |opt|
        attr_value = opt.attribute(attribute)
        match = if regex
          attr_value =~ /#{val}/
        else
          attr_value == val
        end
        #          if attr_value == val
        #              el.click
        if match
          loc = locator.to_s.split(/'/)
          opt.click
          unless noscript
            selenium.run_script("$('##{loc[1]}').change()") if selenium.ie? and loc[1]
          end
          return opt
        end
        options.push attr_value
      end
    end
    raise OatsTestError, "Could not find #{val} among options: #{options.inspect}"
  end

  def gettagid(locator, select_tag = 'option', attribute = 'text')
    oats_debug "Store #{locator} ids by tag_name #{select_tag}"
    el = element?(locator)
    raise OatsTestError, "Could not find #{locator} among options:" if !el
    el.find_elements(:tag_name,select_tag).collect { |opt| opt.attribute(attribute)}
  end

  # wait_for_element followed by a select
  def wait_and_select(locator, value, noscript = nil, select_tag = 'option')
    select(wait_for_element(locator), value, noscript, select_tag)
  end

  def open(url)
    url = Oats::Oselenium.remote_webdriver_map_file_path(url)
    if @osel.login_base_url.nil? or @osel.login_base_url == @osel.base_url or @osel.login_base_url =~ /http.*/
      oats_debug "opening URL [#{url}]"
    else
      url = @osel.login_base_url + url
      oats_debug "opening non-base URL [#{url}]"
    end
    navigate.to(url)
  end

  def get_row(locator,col_tag)
    locator = locator + '//' + col_tag
    arr = elements(locator).collect{|el| el.text}
    return arr
  end

  def get_table(locator)
    arr = []
    selenium.wait_for_element("//div[@id='#{locator}']")
    arr[0] = get_row("//div[@id='#{locator}']//thead/tr",'th[not(contains(@style,"display: none;"))]')
    for row in 1..100
      #        loc = "//div[@id='#{locator}']//tbody/tr[#{row}]"
      row_array = get_row("//div[@id='#{locator}']//tbody/tr[#{row}]",'td[not(contains(@style,"display: none;"))]')
      break if row_array.empty?
      arr[row] = row_array
    end
    return arr
  end
  # Returns locator if /value/ =~ text in any of the locators, or
  #   false if element is not found, nil otherwise
  def text?(value, *locators)
    locators.flatten!
    found = nil
    value_reg = value.instance_of?(Regexp) ? value : /#{value}/
    if locators.empty?
      Oats.warn "Please include a locator to more speficifically locate text: [#{value}]"
      #        if webdriver?
      locators = [Locator.new('body',:tag_name)]
      #        else
      #          found = is_text_orig(value)
      #        end
    end
    locator = false
    found = locators.find do |loc|
      #        if webdriver?
      elems = elements(loc)
      if elems and !elems.empty?
        elems.find { |el|
          if el.displayed?
            locator = true
            value_reg =~ el.text
          end
        }
      end
      #        else
      #          if loc
      #            begin
      #              if element?(loc) and visible?(loc)
      #                locator = true
      #                value_reg =~ text_orig(loc)
      #              end
      #            rescue  Selenium::CommandError => exc
      #              raise unless exc.message =~ /Element .* not found/
      #            end
      #          end
      #        end
    end if found.nil?
    oats_debug('text? '+(found ? 'found' : 'could not locate' ) +" [#{value}] at #{locators}")
    if found
      found
    else
      locator ? nil : false
    end
  end

  # Returns nil, text, or array of texts found at locator(s)
  def text(locators)
    #      txt = if webdriver?
    texts = elements(locators).collect{|el| el.text}
    txt = case texts.size
    when 0 then nil
    when 1 then texts[0]
    else texts
    end
    #      else
    #        text_orig(locators)
    #      end
    oats_debug "text(s) at #{locators}: #{txt.inspect}"
    txt
  end

  # Complete the text in locator to value if necessary and return locator
  # If webdriver, set retype to true if you want to clear the input and retype.
  # If you just want to type value without clearing the element, set retype=>nil.
  def type(locator, value, retype = false, delay = false)
    value = value.to_s
    #      if webdriver?
    locator = element?(locator)
    el = locator.element
    if retype
      xtra = value
      locator.element.clear
    else
      old = el[:value]
      xtra = value.sub(/^#{old}/,'')
      el.clear if xtra == value and old != '' and !retype.nil?
    end
    if xtra == ''
      if old == ''
        oats_debug "type skipping already existing '#{value}' at #{locator}"
      elsif xtra == value
        oats_debug "type cleared already existing '#{old}' at #{locator}"
      end
    else
      oats_debug "type '#{xtra}' at #{locator}"
      if delay
        xtra = xtra.split(//)
        for i in 0..xtra.length
#          selenium.sleep 1
          el.send_keys(xtra[i])
        end
      else
        el.send_keys(xtra)
      end
    end
    #      else
    #        locator ||= @last_locator
    #        oats_debug "type '#{value}' at #{locator}"
    #        type_orig(locator, value)
    #      end
    return locator
  end

  def wait_and_type(locator, value,  options = nil, delay = nil)
    options ||= {}
    retype =  options.delete(:retype) if options.key?(:retype)
    loc = wait_for_element(locator, options)
    type(loc, value, retype, delay)
  end

  def type_keys(locator, value, retype = false)
    #      if webdriver?
    type(locator, value, retype)
    #      else
    #        if retype
    #          oats_debug "type_keys cleared already existing text at #{locator} "
    #          type_orig(locator,"")
    #        end
    #        oats_debug "type_keys '#{value}' at #{locator} "
    #        type_keys_orig(locator, value)
    #      end
  end

  # Press the return key into the input field
  def type_return(locator)
    #      if webdriver?
    type(locator,"\n")
    #      else
    #        key_press(locator||@last_locator, "\\13")
    #      end
  end

  # Waits as in wait_for_element and then clicks on the locator
  # If wait_for_element succeeds, returns locator, else nil
  def wait_and_click(locator, options = {})
#    options[:extra_seconds] ||= 1 if selenium.chrome?
    loc = wait_for_element(locator, options)
    return nil unless loc
    click(loc)
  end

  # Clicks on the element if running webdriver, else does a selenium mouse_over after waiting for element.
  def wait_and_mouse_over(locator)
    #      if webdriver?
    wait_and_click(locator)
    #      else
    #        wait_for_element(locator)
    #        selenium.mouse_over(locator)
    #      ends
  end

  # Waits using Oats.wait_until the value matches any of the locators
  # If succeeds returns locator, else registers Oats.error and returns false
  # options
  #    :is_anywhere => true  Will return true if text appears anywhere on the page
  def wait_for_text(value, locators, options = nil)
    options ||= {}
    skip_error =  options.delete(:skip_error) if options.key?(:skip_error)
    is_anywhere =  options.delete(:is_anywhere) if options.key?(:is_anywhere)
    is_anywhere = false if webdriver?
    oats_debug "wait_for_text #{value.inspect}"
    loc = wait_for_element(locators, options) do |l|
      is_anywhere ? text?(value) : text?(value, l)
    end
    if loc
      text?(value, loc)
    elsif skip_error == 'fail'
      if loc == element?(locators)
        actual = text(loc)
        Oats.error "Expected #{value}, but received #{actual}" unless actual =~ /#{value}/
      else
        Oats.error "Missing text #{value}"
      end
    end
  end


  # Returns Locator if found in any of the locator(s array), or raises OatsTestError
  # Sets selenium.last_locator and selenium.last_element
  # See Oats.wait_until for definition of options hash,
  # Waits for options[:extra_seconds] if specified
  def wait_for_element(locators, *options)
    locators = [locators] unless locators.instance_of?(Array)
    wait_opts = {}
    while o = options.shift
      if o.instance_of?(Hash)
        wait_opts = o
      else
        locators.push o
      end
    end
    wait_opts[:message] ||= "Could not find locator: #{locators}"
    extra_seconds = wait_opts.delete(:extra_seconds) if wait_opts[:extra_seconds]
    time = wait_opts[:seconds] ? "#{wait_opts[:seconds].to_s} seconds " : ''
    oats_debug "wait #{time}for #{locators}"
    @last_locator = nil
    found = nil
    save_debug = @no_oats_debug
    Oats.wait_until wait_opts do
      locators.find do |loc|
        found = element?(loc)
        #          if webdriver?
        found = nil if found and not found.element.displayed?
        #          else
        #            begin
        #              if found and selenium.visible?(loc)
        #                found = loc
        #              else
        #                found = nil
        #              end
        #            rescue  Selenium::CommandError => exc
        #              found = nil unless exc.message =~ /Element .* not found/
        #            end
        #          end
        if found and block_given?
          @no_oats_debug = true
          yield found
        else
          found
        end
      end
    end
    @no_oats_debug = save_debug
    oats_debug "found locator: #{found}" if found and locators.size > 1
    if extra_seconds && !Oats.data('selenium.no_extra_sleep')
      oats_debug "is waiting #{extra_seconds} extra seconds for #{locators}"
      sleep extra_seconds
    end
    @last_locator = found if found
    return found
  ensure
    @no_oats_debug = save_debug
  end

  def oats_debug(output)
    options ||= {}
    Oats.debug('Webdriver '+output) unless @no_oats_debug
  end

  def sleep(seconds, browser = nil)
    return if Oats.data('selenium.no_extra_sleep')
    browser_match = browser.nil? or Oats.data('selenium.browser_type') =~ /#{browser}/
    if browser_match
      oats_debug "sleep #{seconds} extra seconds"
      Kernel.sleep seconds
    end
  end

  def wait_until_loaded(options = {})
    #    puts '------------------'
    #    src = selenium.get_html_source
    #    puts src
    #    puts '------------------'
    options[:message] = "Did not finish loading"
    Oats.wait_until(options) do
      if selenium.element?("//div[@class = 'loading' and not (contains(@style, 'display: none'))]")
        oats_debug 'noticed loading...'
        true
      else
        oats_debug 'waiting to see loading...'
        false
      end
    end
    Oats.wait_until(options) do
      if selenium.element?("//div[@class = 'loading' and not (contains(@style, 'display: none'))]")
        oats_debug 'finished loading...'
        false
        oats_debug 'still loading...'
      else
        true
      end
    end
  end



  def refresh
    oats_debug "refresh page"
    navigate.refresh
  end


  alias_method :location, :current_url
  alias_method :mouse_down, :click
  alias_method :key_press, :type

  def run_script(*args)
    execute_script(*args)
  end

  def get_attribute(locator)
    oats_debug "get_attribute #{locator}"
    loc, val = locator.split(/\/@/)
    element?(loc).attribute(val)
  end

  # Somehow the rescue below doesn't work if I move this code to Oats::Selenium::Api
  # Returns first Locator matching locator or nil. See find_element for ehow choices.
  # Input parameter is one or an array of locator inputs.
  def element?(*locator_args)
    return @last_locator if locator_args.empty?
    found = nil
    locator_args.each do |loc|
      begin
        if loc.instance_of?(String) or loc.instance_of?(Array)
          locator = Oats::Locator.new(loc)
        else
          locator = loc
        end
        locator.element = find_element(locator.ehow, locator.what)
        if locator.element
          found = locator
        end
      rescue Selenium::WebDriver::Error::NoSuchElementError
      end
    end
    return @last_locator = found
  end


  # Returns array of elements matching locator. Last locator is first matching elemnet
  def elements(*locator_args)
    return @last_locator if locator_args.empty?
    if locator_args[0].instance_of?(Oats::Locator)
      locator = locator_args[0]
    else
      locator = Oats::Locator.new(*locator_args)
    end
    elements = find_elements(locator.ehow, locator.what)
    #    elements.empty?
    locator.element = elements
    @last_locator = locator
    return elements

  end

  def select_frame(locator)
    fid = selenium.get_attribute locator+'/@id'
    selenium.switch_to.frame(fid)
  end

  def navigate_back
    selenium.navigate.back
  end

  def wait_for_page_to_load
    return
  end

  def switch_to_default_content
    selenium.switch_to.default_content
  end

  def element_size(locator)
    el_size = selenium.find_element(:xpath, locator).size
    img_size = el_size.width.to_s + "x" + el_size.height.to_s
  end

  def get_cookie_by_name(cookie)
    selenium.manage.cookie_named(cookie)
  end

  def cookies
    all_my_cookies = selenium.manage.all_cookies
    cookies_str = ""
    all_my_cookies.each do |my_cookie|
      cookies_str = cookies_str + my_cookie[:name].to_s + "=" + my_cookie[:value].to_s + "; "
    end
    return cookies_str
  end

  def delete_cookie(cookie, options)
    selenium.manage.delete_cookie(cookie)
  end

  def delete_all_cookies
    selenium.manage.delete_all_cookies
  end

  def style(locator, prop_value)
    element(locator).style(prop_value)
  end
end
