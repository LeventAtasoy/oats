Oats.info "Running"
3.times do |i|
  Oats.add_test "method_test", "testid_#{i}", "parameter_#{i}"
end