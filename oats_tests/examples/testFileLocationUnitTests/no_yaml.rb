fname = File.basename(Oats.test.path)
Oats.info "Running #{fname}"
Oats.add_test fname.sub(/\.rb\z/,"_added.extn")
