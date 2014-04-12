# Selenium 2Original webdriver, using original webdriver api.

Oats.data("selenium")["webdriver"] = true
Oats.browser "http://google.com"
Oats.assert_equal 'Google', selenium.title
element = selenium.find_element(:name, 'q')
element.send_keys "Hello selenium!"

selenium.quit