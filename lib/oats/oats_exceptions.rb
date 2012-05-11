# Defines general exception classes used in OATS.

# Not an error, but a request to exit gracefully from deep within OATS code.
class OatsExit < StandardError ; end

# Unclassified exceptions used by OATS framework
class OatsError < StandardError ; end

# Errors related to Oats Setup
class OatsSetupError < OatsError ; end

# Commandline or related oats-user.yml value errors
class OatsBadInput < OatsError ; end

# Assertion of failure of an individual OATS test
class OatsTestError < OatsError ; end

# Raised by Oats.assert_* methods
class OatsAssertError < OatsTestError ; end

# Assertion of failure during verification of test output
class OatsVerifyError < OatsTestError ; end

# Not an error, but a way to escape a OatsTest from the middle of it.
class OatsTestExit < OatsTestError ; end