require 'oats_x'
class Business < OatsX

  def self.common(c)
    Oats.info "Executing #{c} " + Oats.xl.inspect
  end

  def self.component1
    self.common 'component1'

  end

  def self.component2
    self.common 'component2'
    #    selenium = Oats.browser('http://google.com')
    #    selenium.type("id=gbqfq", 'xxxx')
    #    selenium.click("id=gbqfb")
    #
    #    selenium.find_element(:id, "gbqfq").clear
    #    selenium.find_element(:id, "gbqfq").send_keys "xxxx"
    #    selenium.find_element(:id, "gbqfb").click
  end

  def self.component3
    self.common 'component3'
  end

end
