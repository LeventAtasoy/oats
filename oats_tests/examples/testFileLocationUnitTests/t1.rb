fname = File.basename(Oats.test.path)
Oats.info "Running #{fname}"
Oats.add_test(fname.sub(/\.rb/,".extn"))
Oats.add_test(fname.sub(/\.rb/,".yml"))
