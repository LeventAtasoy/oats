Oats.info Oats.data("mytest")
copied_yml = Oats.test.path.sub(/\.#{Oats.test.is_file}/,'_1.yml')
Oats.yaml copied_yml if File.exist?(copied_yml)
Oats.info Oats.data("mytest")