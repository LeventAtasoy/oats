module Oats
  class Email
    class << self

      # Assumes at least opts[:to] is specified as an an address or an array of 'email: address' entries
      def send(opts)
        message = {
            :subject => opts['subject'],
            :text => opts['text'],
        }
        message[:to] = []
        to_list = opts['to'].instance_of?(Array) ? opts['to'] : [opts['to']]
        to_list.each do |i|
          item = if i.instance_of?(Hash)
                   {:email => i['email'], :name => i['name']}
                 else
                   {:email => i, :name => nil}
                 end
          message[:to].push(item)
        end
        message[:from_email] ||= message[:to].first[:email]
        message[:from_name] ||= message[:to].first[:name]
        message[:attachments] = opts['attachments'] if opts['attachments']
        message[:html] = opts['html'] if opts['html']
        message[:text] = opts['text'] if opts['text']

        if opts['host'].nil?
          require 'mandrill'
          @@m ||= Mandrill::API.new Oats.data 'email.password'
          result = @@m.messages.send message
          Oats.info "Email result: #{result}"
        else
          require 'net/smtp'
          Net::SMTP.start(opts['host'], opts['port'], opts['domain'], opts['username'], opts['password'], :plain) do |smtp|
            message[:to].each do |addressee|
              msg = "From: #{message[:from_name]} <#{message[:from_email]}>\n" +
                  "To: <#{addressee[:email]}>\n" +
                  "Subject: #{message[:subject]}\n\n" +
                  message[:text]
              smtp.send_message msg, opts['from_email'], addressee[:email]
              Oats.info "Email sent to: #{addressee[:email]}"
            end
          end
        end
      end

    end
  end
end