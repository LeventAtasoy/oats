# To change this template, choose Tools | Templates
# and open the template in the editor.

require 'oats/oats_selenium_api'
require 'oats/oats_x'
require 'net/imap'
#require 'openssl'
#require 'nokogiri'

class SampleXlLists < Oats::Keywords

  # Maps entries to be accessed by 'locator' function for Proactiv
  self::LOCATOR_MAP = {
    'url' =>	"url_locator"
  }

  class << self

    def action1
      data = oats_data
      data.delete('keywords')
      Oats.info "Data:" + data.inspect
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

