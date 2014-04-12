# Raising any exceptions will quit processing the test BY designating it as FAIL.
# *  OatsTestError:   Use for any generic test execution exception
# *  OatsVerifyError: Use for to quit processing during output verification. See
#    example/verifyException
# DO NOT USE 'exit'.
# * Use Oats.error to register failures during execution.
# * See example/basic for how to use Oats.error

begin # Exceptions raised within this block will
      # be caught by the following rescue clauses
  Oats.info "If something unexpected happens here, like division by zero,"
  Oats.info "the second catch-all rescue will get it."
  1/0

rescue Errno::ENOENT # Handled here, no problem
  Oats.warn "Rescued exception's message: " + $!
  Oats.warn "This was expected. Here is the full stack trace:"
  Oats.warn $! # Print stack strace only if warranted

rescue # All other types of exceptions
  Oats.warn "Got it: " + $!
  Oats.warn "If you don't know how to handle it fully, push it up the chain."
  Oats.info "OATS will catch it automatically and mark the test as failed."
  raise $!

ensure # If you need something that always gets executed, even after exceptions
  Oats.info "Do some test cleanup right here."
end

Oats.info "Due to raised exception above, this will not get executed."
