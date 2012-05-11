module EventMachine

  def self.event_callback conn_binding, opcode, data # :nodoc:
    #
    # Changed 27Dec07: Eliminated the hookable error handling.
    # No one was using it, and it degraded performance significantly.
    # It's in original_event_callback, which is dead code.
    #
    # Changed 25Jul08: Added a partial solution to the problem of exceptions
    # raised in user-written event-handlers. If such exceptions are not caught,
    # we must cause the reactor to stop, and then re-raise the exception.
    # Otherwise, the reactor doesn't stop and it's left on the call stack.
    # This is partial because we only added it to #unbind, where it's critical
    # (to keep unbind handlers from being re-entered when a stopping reactor
    # runs down open connections). It should go on the other calls to user
    # code, but the performance impact may be too large.
    #
    if opcode == ConnectionUnbound
      if c = @conns.delete( conn_binding )
        begin
          c.unbind
        rescue
          @wrapped_exception = $!
          stop
        end
      elsif c = @acceptors.delete( conn_binding )
        # no-op
      else
        # raise ConnectionNotBound, "recieved ConnectionUnbound for an unknown signature: #{conn_binding}"
      end
    elsif opcode == ConnectionAccepted
      accep,args,blk = @acceptors[conn_binding]
      raise NoHandlerForAcceptedConnection unless accep
      c = accep.new data, *args
      @conns[data] = c
      blk and blk.call(c)
      c # (needed?)
    elsif opcode == ConnectionCompleted
      c = @conns[conn_binding]
      if c
        c.connection_completed
        # else
        # raise ConnectionNotBound, "received ConnectionCompleted for unknown signature: #{conn_binding}"
      end
      ##
      # The remaining code is a fallback for the pure ruby and java reactors.
      # In the C++ reactor, these events are handled in the C event_callback() in rubymain.cpp
    elsif opcode == TimerFired
      t = @timers.delete( data )
      return if t == false # timer cancelled
      t or raise UnknownTimerFired, "timer data: #{data}"
      t.call
    elsif opcode == ConnectionData
      c = @conns[conn_binding] or raise ConnectionNotBound, "received data #{data} for unknown signature: #{conn_binding}"
      c.receive_data data
    elsif opcode == LoopbreakSignalled
      run_deferred_callbacks
    elsif opcode == ConnectionNotifyReadable
      c = @conns[conn_binding] or raise ConnectionNotBound
      c.notify_readable
    elsif opcode == ConnectionNotifyWritable
      c = @conns[conn_binding] or raise ConnectionNotBound
      c.notify_writable
    end
  end
end