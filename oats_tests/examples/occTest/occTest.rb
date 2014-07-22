Oats.info "Running #{Oats.test.name}"
file = "#{ENV['OATS_USER_HOME']}/#{Oats.test.name}"
total = Oats.data['count'] || 1
interval = Oats.data['interval'] || 1
total.times do |i|
  Oats.info "Count is #{i}, no file #{file}"
  if File.exists? file
    Oats.info "Found file #{file}"
    File.mv file, file+'.x'
    break
  end
  sleep interval
end