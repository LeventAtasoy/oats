
module Oats

  # Process keyword driven testing
  class Keywords
    class << self

      # Same as selenium.wait_and_type, but maps key via OatsX.locator, and uses
      # OatsX.data[key] for value
      def wait_and_type(key, *args)
        selenium.wait_and_type(locator(key), oats_data[key], *args)
      end

      # Same as selenium.wait_for_element, but maps key via OatsX.locator first
      def wait_and_click(key)
        selenium.wait_and_click(locator(key))
      end

      # Same as selenium.wait_for_element, maps key via OatsX.locator first
      def wait_and_text(key)
        selenium.wait_for_element(locator(key)).text
      end

      # Returned the key or mappings if defined in the <class>::LOCATOR_MAP
      def locator(key)
        self::LOCATOR_MAP[key] || key
      end


      # Return data from XL spreadsheet entries via Oats.data('xl.data')
      # OatsX.oats_data(key_string) or OatsX.oats_data[key_string]
      def oats_data(cell = nil, clas = self)
        xl_root = $oats[clas.name]
        list = xl_root['list'] || Oats.data('keywords.list')
        if list
          xl_root_list = xl_root[list]
        else
          xl_root_list =  xl_root
        end
        #        Oats.assert list, "Oats.data keywords.list is not defined."
        val = cell ? xl_root_list[cell] : xl_root_list
        Oats.assert( val, "No keywords are defined for #{clas}" + (list ? ".#{list}" : '') ) if cell == 'keywords'
        Marshal.load(Marshal.dump(val)) # Protect Oats.data from modification
      end

      # Handles keyword processing.
      # Used by OATS framework to run XL driven test suites.
      # Users can also call this from yaml_handlers.
      def process
        # Class name comes from Oats.data oats_keywords_cleass, or in the case of XL files from TestCase ID
        class_name = Oats.data('keywords.class') || File.basename(File.dirname(File.dirname(Oats.test.id)))
        class_file = nil
        begin
          keywords_class = Kernel.const_get class_name
        rescue NameError
          class_file = Oats.data('keywords.class_file')
          unless class_file # Try standard ruby conventions
            class_file = class_name.dup
            class_file.gsub!(/::/, '/')
            class_file.gsub!(/([A-Z]+)([A-Z][a-z])/,'\1_\2')
            class_file.gsub!(/([a-z\d])([A-Z])/,'\1_\2')
            class_file.tr!("-", "_")
            class_file.downcase!
          end
          begin
            Oats.info "Loading: '#{class_file}' for #{class_name}"
            require class_file
            begin
              keywords_class = Kernel.const_get class_name
            rescue NameError
              raise OatsTestError, "Can not find class '#{class_name}' in class file: '#{class_file}'"
            end
          rescue LoadError
            Oats.assert class_file.nil?, "Could not load Oats.data keywords.class_file '#{class_file}' for class '#{class_name}'."
          end
        end
        oats_data('keywords',keywords_class).each do |action|
          Oats.assert keywords_class.respond_to?(action),
            "There is no method defined in #{class_name} to the handle keyword 'a#{action}'."
          Oats.info "Performing " + action
          keywords_class.send action
        end
      end

    end
  end
end
