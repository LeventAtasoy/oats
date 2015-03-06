#require 'yaml'            # http://www.ruby-doc.org/core/classes/YAML.html

# HOSTNAME is needed to properly resolve ENV[HOSTNAME] references that may exist inside YAMLS
# when this module is called from outside Oats framework
require 'rbconfig'
ENV['HOSTNAME'] ||= RbConfig::CONFIG['host_os'] =~ /mswin|msys|mingw|cygwin|bccwin|wince|emc/ ?
    ENV['COMPUTERNAME'] : `hostname`.chomp

module Oats

  # Keeps history of YAML files loaded into the global $oats.
  # if omit is true add the yaml name into the result directory hierarchy
  class OatsDataLoadHistoryItem
    attr_accessor :file, :omit, :in_result_dir

    def initialize(file, omit = false)
      @file = file
      @omit = omit
      @in_result_dir = true
    end
  end

  class OatsData
    @@oats_def_file = nil
    @@resolve_path = []
    # Resolves ENV[ entries in a oats_data
    def OatsData.resolve(oats_data = nil)
      oats_data = $oats unless oats_data
      changed = false
      oats_data.each do |key, val|
        if val.instance_of?(String)
          begin
            next unless /Oats\.|ENV\[/ =~ val # skip if no need for change
            new_val = eval(val)
            next if new_val.instance_of?(String) and /Oats\.|ENV\[/ =~ new_val # skip if change did not help
            #          new_key = key.sub(/\s*\(wait4definition\)\s*/,'')
            #          next unless new_key == key or new_val # skip if wait4defs in effect
            #          oats_data[new_key] = new_val
            oats_data[key] = if new_val == 'previous_oats_value'
                               oc = @@oats_copy
                               @@resolve_path.each { |k| oc = oc[k] }
                               oc[key]
                             else
                               new_val
                             end
            changed = true
              #          oats_data.delete(key) unless new_key == key
          rescue Exception => e
            Oats.error "While evaluating Oats.data #{key}: #{val}"
            raise e
          end
        elsif val.instance_of?(Array)
          val.each_with_index do |item, index|
            if item.instance_of?(String)
              begin
                next unless /Oats\.|ENV\[/ =~ item # skip if no need for change
                new_val = eval(item)
                next if /Oats\.|ENV\[/ =~ new_val # skip if change did not help
                val[index] = if new_val == 'previous_oats_value'
                               oc = @@oats_copy
                               @@resolve_path.each { |k| oc = oc[k] }
                               oc[key]
                             else
                               new_val
                             end
                changed = true
              rescue Exception => exc
                Oats.error "While evaluating [#{item}] for [#{index}]th entry in Rat.data #{key}: #{val}"
                raise exc
              end
            elsif item.instance_of?(Hash)
              begin
                @@resolve_path.push(key)
                res_return = resolve(item)
              ensure
                @@resolve_path.pop
              end
              changed = res_return || changed
            end
          end
        elsif val.instance_of?(Hash)
          begin
            @@resolve_path.push(key)
            res_return = resolve(val)
          ensure
            @@resolve_path.pop
          end
          changed = res_return || changed
        end
      end
      while changed
        changed = resolve(oats_data)
      end
      changed
    end

    # If no input, use default YAML file, overridden by user's HOME or OATS_INI
    # Specified oats_file becomes the overriding file.
    # If specified, oats_default data is used instead of the default YAML contents.
    # Returns loaded data in $oats
    @@define_always = nil
    @@aut_ini = nil

    def OatsData.load(oats_file = ENV['OATS_INI'], oats_default = nil)
      @@merged_path = nil # Keep track of merged Oats.data hash key path
      @@define_always = nil
      @@oats_def_file ||= ENV['OATS_HOME'] + '/oats_ini.yml'

      if oats_file
        raise(OatsError, "Can not locate: #{oats_file}") unless File.exist?(oats_file)
      else
        oats_file = ENV['OATS_USER_HOME'] ? File.join(ENV['OATS_USER_HOME'], 'oats_user.yml') : nil
        oats_file = nil unless oats_file and File.exist?(oats_file)
      end
      if oats_file
        begin
          oats_data = YAML.load_file(oats_file)
        rescue
          raise(OatsError, "While loading [#{oats_file}]: #{$!}")
        end
      end

      if oats_default # make a deep copy
        oats_default = Marshal.load(Marshal.dump(oats_default))
      else # Only the first time, when reading the _ini files
        begin
          oats_default = YAML.load_file(@@oats_def_file)
        rescue
          raise(OatsError, "Error loading [#{@@oats_def_file}]: " + $!)
        end
        $oats = oats_default # So that resolve can resolve Oats.data calls
        begin
          OatsData.resolve(oats_default)
        rescue
          $log.error "While resolving variables in: " + @@oats_def_file
          #         raise(OatsError, $!.to_s)
          raise $!
        end
        # Use this hash to persist internally used oats_data
        oats_default['_'] = {}
        oats_default['_']['load_history'] = [OatsDataLoadHistoryItem.new(@@oats_def_file)]
        $oats = oats_default # $oats now has data resolved and has load_history
        # For some reason OCC/Ubuntu needed the environment but not Mac
        aut_dir_test = ENV['OATS_TESTS'] || oats_data['execution']['dir_tests'] || oats_default['execution']['dir_tests']
        if aut_dir_test
          aut_ini = aut_dir_test + '/aut_ini.yml'
          @@aut_ini = oats_default['include_yaml'] ||= aut_ini if File.exists?(aut_ini)
        end
        OatsData.include_yaml_file(oats_default['include_yaml'], @@oats_def_file) if oats_default['include_yaml']
        oats_default = $oats
      end

      if oats_data
        incl_yamls = oats_data['include_yaml']
        if incl_yamls and not oats_data['include_yaml_later']
          oats_data['include_yaml'] = nil
          OatsData.include_yaml_file(incl_yamls, oats_file)
        end
        begin
          @@oats_copy = Marshal.load(Marshal.dump($oats))
          merged = OatsData.merge($oats, oats_data)
        rescue OatsError
          $log.error "While merging: " + oats_file
          raise(OatsError, $!.to_s)
        rescue
          $log.error "While merging: " + oats_file
          raise
        end
        merged['_']['load_history'] << OatsDataLoadHistoryItem.new(oats_file)
        $oats = merged
        if incl_yamls and oats_data['include_yaml_later']
          merged['include_yaml'] = nil
          OatsData.include_yaml_file(incl_yamls, oats_file)
        end
        begin
          OatsData.resolve(merged)
        rescue
          $log.error "While resolving variables in: " + oats_file
          raise $!
        end
        result = $oats
      else
        $log.warn("Could not find oats-user.yml via OATS_INI or HOME definition. Using the system default.")
        result = oats_default
      end
      return result
    end

    @@include_hist = []
    # Handles include_yaml files. Calls OatsData.overlay to modify $oats. Returns nothing.
    def OatsData.include_yaml_file(incl_yamls, oats_file = nil)
      return unless incl_yamls
      if incl_yamls
        incl_yamls = [incl_yamls] if incl_yamls.instance_of?(String)
        incl_yamls.each do |incl_yaml|
          begin
            incl_yaml_file = File.exists?(incl_yaml) ? incl_yaml : File.expand_path(incl_yaml, File.dirname(oats_file))
            # puts 'yf1: ' + incl_yaml_file.inspect
            incl_yaml_file = File.exists?(incl_yaml_file) ? incl_yaml_file : TestData.locate(incl_yaml, File.dirname(oats_file))
            Oats.assert incl_yaml_file, "Can not locate file: #{incl_yaml}"
            hist = Oats.data['_']['load_history'].collect { |i| i.file } + @@include_hist
            Oats.assert !hist.include?(incl_yaml_file), "Attempt to re-include #{incl_yaml_file} into #{hist.inspect}"
            begin
              @@include_hist.push(incl_yaml_file)
              OatsData.overlay(incl_yaml_file)
            ensure
              Oats.assert_equal incl_yaml_file, @@include_hist.pop
            end
          rescue
            msg = "While including [#{incl_yaml}]"
            msg += " from: " + oats_file if oats_file
            #          raise(OatsError, msg + $!)
            Oats.error msg
            raise $!
          end
        end
        return
      end
    end

    # Returns Oats.data history files in an array.
    def OatsData.history(omit=false)
      if omit
        Oats.data['_']['load_history'].select { |i| i.omit and i.in_result_dir }.collect { |i| i.file }
      else
        Oats.data['_']['load_history'].collect { |i| i.file }
      end
    end

    # Overrides config_ini hash tree with custom_ini.
    # At each level keep only the items specified by the include_list array
    def OatsData.merge(config_ini, custom_ini)
      merged_config = config_ini
      unless config_ini.class == Hash
        if config_ini.nil?
          custom_ini.delete('(define)') if  custom_ini.has_key?('(define)')
          return custom_ini
        else
          raise(OatsError, ".. previous Oats.data '#{@@merged_path}' is not a hash: " + config_ini.inspect)
        end
      end
      return config_ini unless custom_ini # If input YAML is empty
      raise(OatsError, ".. override YAML is not a hash: " + custom_ini.inspect) unless custom_ini.class == Hash
      include_array = []
      include_list_exists = false
      @@define_always = custom_ini['define_always'] if custom_ini.include?('define_always')
      custom_ini.each do |key, val|
        if config_ini.has_key?(key)
          old_val = config_ini[key]
          unless old_val.nil? or val.nil?
            if (old_val.class != val.class)
              if val.instance_of?(FalseClass) # If new value is different and false set it to nil
                val = nil
              elsif not ((val.instance_of?(TrueClass) or val.instance_of?(FalseClass)) and
                  (old_val.instance_of?(TrueClass) or old_val.instance_of?(FalseClass)))
                Oats.error "Entry [#{key}] was previously set to [#{old_val}] with type [" + old_val.class.to_s + "]"
                Oats.error "  now being set to [#{val}] with type [" + val.class.to_s + "]"
                Oats.error "  entry [#{old_val}] of the original YAML entry is part of: " + config_ini.inspect
                Oats.error "  entry [#{val}] of over-ride YAML entry is part of: " + custom_ini.inspect
                raise(OatsError, ".. attempt to override OATS data with a different type.")
              end
            end
          end
        else
          if key == "include_list"
            raise(OatsError, "The include_list " + val.inspect + " is not an Array") unless val.class == Array
            include_array = val
            include_list_exists = true
          else
            add_key = key.sub(/\s*\(define\)\s*/, '')
            if add_key == key and !@@define_always
              master_file = @@aut_ini || @@oats_def_file
              raise(OatsError, ".. override Oats.data '#{key}' is not included into: " + master_file)
            else
              if merged_config.has_key?(add_key)
                key = add_key
                old_val = config_ini[key]
              else
                merged_config[add_key] = val
                merged_config.delete(key) unless add_key == key
                next
              end
            end
          end
        end
        case val
          when Hash then
            merged_path = @@merged_path
            @@merged_path = @@merged_path ?  @@merged_path + '.'  + key : key
            merged_config[key] = merge(old_val, val) # Deep copy for Hashes
            @@merged_path = merged_path
          when Array then # Only shallow copy for Arrays
            new_arr = []
            val.each { |e| new_arr << e }
            merged_config[key] = new_arr
          when String then
            merged_config[key] = val.dup
          else
            unless (val.nil? and (old_val.class == Hash)) || key == "include_list"
              merged_config[key] = val
            end
        end
      end
      if include_list_exists
        return nil if  include_array.nil?
        merged_config.delete_if { |key, value| not include_array.include?(key) }
      end
      merged_config
    end

    # Overlays $oats with contents of oats_file. Performs no compatibility checking.
    def OatsData.overlay(oats_file)
      if oats_file.instance_of?(Hash)
        oats_overlay = oats_file
        oats_file = oats_overlay.keys.first + '_' + oats_overlay.values.first.keys.first
      else
        if oats_file
          raise(OatsError, "Can not locate [#{oats_file}]") unless File.exist?(oats_file)
        else
          raise(OatsError, "Must specify a oats_file")
        end
        begin
          oats_overlay = YAML.load_file(oats_file)
        rescue
          raise(OatsError, "While loading [#{oats_file}] #{$!}")
        end
      end
      unless oats_overlay
        Oats.warn "Skipping empty YAML file: #{oats_file}"
        return $oats
      end
      incl_yamls = oats_overlay['include_yaml']
      if incl_yamls and not oats_overlay['include_yaml_later']
        oats_overlay['include_yaml'] = nil
        OatsData.include_yaml_file(incl_yamls, oats_file)
      end
      # Clone it, don't change the original
      oats_new = Marshal.load(Marshal.dump($oats))
      begin
        OatsData.overlay_data(oats_overlay, oats_new)
      rescue OatsError
        Oats.error "While overlaying: " + oats_file
        raise(OatsError, $!.to_s)
      rescue Exception
        Oats.error "While overlaying: " + oats_file
        raise
      end
      oats_new['_']['load_history'] << OatsDataLoadHistoryItem.new(oats_file) if oats_new['_']
      $oats = oats_new
      if incl_yamls and oats_overlay['include_yaml_later']
        oats_overlay['include_yaml'] = nil
        OatsData.include_yaml_file(incl_yamls, oats_file)
      end
      begin
        OatsData.resolve(oats_new)
      rescue
        Oats.error "While resolving variables in: " + oats_file
        raise $!
      end
      oats_new = $oats
      return oats_new
    end

    # Recurse thru matching hash only, replace rest by overlay
    def OatsData.overlay_data(overlay, oats_data)
      overlay.each do |key, val|
        default_key = key.sub(/\s*\((default|define)\)\s*/, '')
        if default_key == key
          default_key = nil
        else
          key = default_key
        end
        if val.instance_of?(Hash)
          if oats_data[key].instance_of?(Hash)
            OatsData.overlay_data(val, oats_data[key])
          else
            oats_data[key] = val if oats_data[key] == nil
            OatsData.overlay_data(val, oats_data[key])
          end
        else
          if default_key
            oats_data[key] = val unless oats_data[key]
          else
            oats_data[key] = val
          end
        end
      end
    end

    # Regenerates input file based on YAML. Assumes input is absolute path and exists.
    # Return generated file path or nil if nothing is generated.
    def OatsData.regenerate_file(file_in)
      file_in_root = file_in.sub(/(.*)\..*$/, '\1')
      file_in_extn = File.extname(file_in)
      yaml_in = file_in_root + '.yml'
      return nil unless File.exist?(yaml_in)
      file_gen = file_in_root + '.gen' + file_in_extn
      yml_out = file_in_root + '.gen.yml'
      $log.debug "Regenerating [#{file_in}] into [#{file_gen}] based on [#{yaml_in}]"
      file_contents = IO.read(file_in)
      test_data = YAML.load_file(yaml_in)
      if OatsData.map_file_contents(Oats.data, test_data, file_contents)
        File.open(file_gen, 'w') { |out| out.print file_contents }
        File.open(yml_out, 'w') { |out| YAML.dump(test_data, out) }
        return file_gen
      else
        return nil
      end
    end

    # Helper method to replace HTML file contents based on oats and test data mappings.
    # Returns true if substitutions are made
    def OatsData.map_file_contents(oats_data, test_data, file_contents)
      return false unless test_data
      changed = false
      test_data.each do |key, val|
        repVal = oats_data[key]
        next if val.nil? or repVal.nil?
        if val.class == Hash
          changed = changed or map_file_contents(repVal, val, file_contents)
        else
          changed = changed or file_contents.sub!(val, repVal)
          test_data[key] = repVal
        end
      end
    end

  end
end
