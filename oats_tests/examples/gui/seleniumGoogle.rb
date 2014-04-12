require 'selenium-webdriver'
selenium = Oats.browser('http://google.com')
#loc = selenium.type("id=gbqfq", 'xxxx')
#selenium.click("id=gbqf")
el = selenium.find_element(:id, "gbqfq")
el.clear
el.send_keys "xxxx"
selenium.find_element(:id, "gbqfb").click


