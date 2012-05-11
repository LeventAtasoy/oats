# Override oats data based on commandline options.
#require 'log4r'  # http://log4r.sourceforge.net/rdoc/index.html
#require 'util'
require 'deep_merge/deep_merge'

module Oats

  module Roptions

    def Roptions.overlay(options)
      opts_array = options['_:options']
      if options['_:json']
        $log.info "Overriding Oats.data with: #{options['_:json']}"
        $oats.deep_merge!(JSON.parse(options['_:json']))
      end
      if opts_array
        opts_array.each do |opt_valu|

          opt, valu = opt_valu.split(/\s*:\s*/)
          data_keys = opt.split('.')
          value = $oats
          until data_keys.size == 1 do
            value = value[key=data_keys.shift]
            Oats.assert value.instance_of?(Hash), "Oats.data #{opt} is not a hash at #{key}"
          end
          $log.info "Option #{opt.inspect} specified as: #{valu.inspect} is overriding #{value[data_keys.first].inspect}"
          value[data_keys.first] = valu
        end
      end
    end

    def Roptions.override(options={})
      oats_data = $oats
      oats_lib = Util.expand_path(File.dirname(__FILE__)+'/..')
      oats_data['_']['oats_lib'] = oats_lib
      options.each do |key,val|
        data_keys = key.split(':')
        v = oats_data
        key_var = nil
        loop do
          key_var = data_keys.shift
          break if data_keys.empty? or key_var == '_'
          v = v[key_var]
        end
        next if key_var == '_'
        if val.instance_of?(Array)
          val_str = val.join(',')
        else
          val_str = val.to_s
        end
        vval = v[key_var]
        if vval.instance_of?(Array)
          vval_str = vval.join(',')
        else
          vval_str = vval.to_s
        end
        $log.info "Option #{key.inspect} specified as: #{val_str.inspect} is overriding #{vval_str.inspect}"\
          unless $oats_execution['agent']
        v[key_var] = val
      end

      # *** Now verify the options ***
      # Ensure log_level valid
      level = Log4r::Log4rConfig::LogLevels.index(oats_data['execution']['log_level'])
      raise(OatsBadInput, "Unrecognized execution:log_level [#{oats_data['execution']['log_level']}]") unless level
      $log.level = level = 1 if $log

      raise(OatsBadInput,"Must specify execution:dir_results") unless oats_data['execution']['dir_results']

      # Fix path to vendor, needed to run under java
      oats_data['_']['vendor'] = Util.expand_path('../vendor',oats_lib)

      # Verify existence of browser to show results
      oats_data['selenium']['ide']['result_browser'] = oats_data['selenium']['ide']['result_browser']
      oats_data['selenium']['ide']['show_result'] = 0 unless oats_data['selenium']['ide']['show_result']

      unless oats_data['selenium']['pause_on_exit']
        if oats_data['execution']['test_files'] and oats_data['execution']['test_files'].first =~ /\.yml/
          oats_data['selenium']['pause_on_exit'] = 0
        else
          oats_data['selenium']['pause_on_exit'] = 1
        end
      end
      return options
    end

  end
end