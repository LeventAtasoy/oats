# Log4r can be configured using YAML. This example uses log4r_yaml.yaml
require 'log4r'
require 'log4r/yamlconfigurator'
# we use various outputters, so require them, otherwise config chokes
require 'log4r/outputter/datefileoutputter'
require 'log4r/outputter/emailoutputter'
include Log4r

cfg = YamlConfigurator # shorthand
cfg['HOME'] = ENV['OATS_USER_HOME']     # the only parameter in the YAML, our HOME directory

# load the YAML file with this
cfg.load_yaml_file('log4r.yaml')

