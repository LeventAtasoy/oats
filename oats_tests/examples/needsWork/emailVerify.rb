#messages = imap.search(["BEFORE", "1-Apr-2003", "SINCE", "1-Apr-2003"])
#messages = imap.search(["TO", "axx@oats.org"])
#messages = imap.search(["BODY", "hello"])
#messages = imap.search(["RECENT"])
#messages = imap.search(["SUBJECT",subj, "SINCE", "5-Jan-2010"])
#message_id = messages.last
#envelope = imap.fetch(message_id, "ENVELOPE")[0].attr["ENVELOPE"]
#puts "#{envelope.from[0].name}: \t#{envelope.date}  \t#{envelope.subject}"

# Email with string on subject
def imap_fetch_gmail(subject_string, dont_wait=nil)
  Oats.assert((subject_string and subject_string != ''), 'Imap can not search for empty string')
  imap_data = Oats.data['imap']
  Oats.assert imap_data['username'] && imap_data['password'] ,
    "Missing Oats.data imap.username or imap.password"
  msg = "emails with subject containing string: " + subject_string
  Oats.info "Waiting for #{msg}"
  body = nil
  Oats.wait_until(error_msg = "Can not find #{msg}", 300) do
    imap = Net::IMAP.new('imap.gmail.com', 993, true)
    imap.login(imap_data['username'], imap_data['password'] )
    imap.select('INBOX')
    found = imap.uid_search(["SUBJECT", subject_string])
    if found.empty?
      Oats.assert !dont_wait, error_msg
      imap.logout
      sleep 5
    else
      Oats.assert found.size == 1, "Too many #{msg}"
      body = imap.uid_fetch(found, "BODY[TEXT]").first.attr["BODY[TEXT]"]
    end
    body
  end
end