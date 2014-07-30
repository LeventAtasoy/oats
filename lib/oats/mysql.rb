#require 'mysql' # http://www.tmtm.org/en/ruby/mysql
require "tempfile"
require 'oats/oats_exceptions'

module Oats
  class OatsMysqlError < OatsTestError ; end
  class OatsMysqlMissingInput < OatsMysqlError ; end
  class OatsMysqlNoConnect < OatsMysqlError ; end
  # Oats.mysql creates an instance of this class to interact with MySQL DBs
  class Mysql

    # See Oats.mysql for more accurate/detailed documentation
    # sql_input:: Path to a file.sql to execute
    # connect:: Override for Oats.data sql:connect
    # returns array of rows of results. Each row is an array of columns.
    def run(sql_input, connect = nil, sql_out_name = nil)
      raise OatsMysqlNoConnect, "Oats.data sql:connect is null" unless Oats.data['sql']['connect']
      test = TestData.current_test
      unless /\s/ =~ sql_input # If there is space in name, assume it is not a file
        abs_path = File.expand_path(sql_input,test.path)
      end
      if File.exist?(abs_path)
        mysql_input_file = OatsData.regenerate_file(abs_path)
        mysql_input_file = abs_path unless mysql_input_file
        name = File.basename(sql_input,'.*')
        sql_input = IO.read(mysql_input_file)
        sql_input = nil if sql_input.length > 200
      else
        tf = Tempfile.new("OatsMysqlInput")
        tf.puts(sql_input)
        tf.close
        mysql_input_file = Util.expand_path(tf.path)
        name = 'mysql_default'
      end
      sql_out_name = name + '.txt' unless sql_out_name
      sql_out = File.join(test.result, sql_out_name) if sql_out_name
      err_file = sql_out + '.err'
      command = (Oats.os == :macosx ? '/usr/local/mysql/bin/mysql' : 'mysql') +
        " #{parameters(connect)} < #{mysql_input_file} > #{sql_out} 2> #{err_file}"
      #    $log.debug "Executing: #{command}"
      $log.info "SQL: #{sql_input}" if sql_input
      FileUtils.mkdir_p(test.out)
      ok = system(command)
      $log.error("MySQL failed with return code: #{$?}") unless ok
      FileUtils.rm_f(err_file) unless File.size?(err_file)
      FileUtils.rm_f(sql_out) unless File.size?(sql_out)
      if File.exist?(err_file)
        errors = IO.readlines(err_file)
        errors.size == 1 or errors[0...-1].each {|line| $log.error line.chomp}
        raise(OatsMysqlError,errors.last.chomp) unless errors.empty?
      end
      rows = IO.readlines(sql_out) if File.exist?(sql_out)
      return [] unless rows
      rows.shift
      if rows[1] =~ /\t/
        return rows.collect{|t| t.chomp.split(/\t/) }
      else
        return rows.collect{|t| t.chomp }
      end
    end


    def processlist
      raise OatsMysqlNoConnect, "Oats.data sql:connect is null" unless Oats.data['sql']['connect']
      sql_out = 'mysql_processlist.txt'
      command = "mysqladmin #{parameters('connect',true)} processlist > #{sql_out}"
      success = system(command)
      $log.error("MySQL failed with return code: #{$?}") unless success
      FileUtils.rm_f(sql_out) unless File.size?(sql_out)
    end

    private

    def parameters(connect,proc_list=false)
      sql = Oats.data['sql']
      connect ||= sql['connect']
      conn = sql[connect]
      user = conn['user']
      err "Oats MySQL requires input for sql:user" unless user
      password = conn['password']
      err "Oats MySQL requires a string input for sql:password" unless password
      password = " -p#{password}" unless password == ""
      host = conn['host']
      err "Oats MySQL requires input for sql:host" unless host
      params = "-u#{user}#{password} -h#{host}"
      return params if proc_list
      db = conn['database']
      err "Oats MySQL requires input for sql:db" unless db
      "#{params} -D#{db}"
    end

    def err(inp)
      raise(OatsMysqlMissingInput,inp)
    end

  end
end
