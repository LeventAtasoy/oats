# Raising any exceptions will quit processing the test BY designating it as FAIL.
# *  OatsTestError:   Use for any generic test execution exception
# *  OatsVerifyError: Use for to quit processing during output verification. See
# *  OatsTestExit:     Use instead of exit to quit processing without error.
# DO NOT USE 'exit'.
# * Use Oats.error to register failures during execution.
# * See example/code for how to use Oats.error

#
# Demonstrate retrieving data stored by aoother test, eg. code
#
t = Oats.global['examples/code:start_time']
if t # ie not nil because previously stored
  Oats.info "Test [code] was started at #{t} and #{t.usec} microseconds."
else
 Oats.info "Test [code] was not previously run in this OATS session."
end

begin # Exceptions raised within this block will
  # be caught by the following rescue clauses
  Oats.info "Try to create ./nonexistent/subdirectory"
  FileUtils.mkdir "./nonexistent/subdirectory"
  
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

Oats.info "We are done with the test."
