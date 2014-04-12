# To change this template, choose Tools | Templates
# and open the template in the editor.

require 'oats/keywords'
require 'net/imap'
#require 'openssl'
#require 'nokogiri'

module SampleXlLists 

  # Maps entries to be accessed by 'locator' method below
  self::LOCATOR_MAP = {
    'url' =>	"url_locator"
  }

  class << self
    include Oats::Keywords

    def action1
      data = oats_data
      data.delete('keywords')
      Oats.info "URL: #{locator('url')} Data:" + data.inspect
    end

    def action2
      action1
    end

    # Invoke the AUT (Application Under Test)
    def invokeApplication
      Oats.browser(oats_data['URL']);
      wait_and_text()
    end


  end
end

