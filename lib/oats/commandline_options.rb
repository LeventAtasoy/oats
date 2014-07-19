require 'optparse' # http://www.ruby-doc.org/stdlib/libdoc/optparse/rdoc/index.html

module Oats

  module CommandlineOptions

    @@OPTIONS = nil
    def CommandlineOptions.options(argv = nil)

      # This should be set only once, coming from unit test or command-line
      $oats_execution['input_args'] = $oats_unit_test ? $oats_unit_test['input_args'] : ARGV.dup

      argv ||= $oats_execution['input_args'].dup
      argv_save = argv.dup

      begin

        # Hold all of the options parsed from the command-line by OptionParser.
        options = {}
        optparse = OptionParser.new do|opts|
          opts.banner = "Usage: oats.rb [options] test1 test2 ..."
          opts.separator "Options:"
          opts.on( '--tests t1,t2,t3', Array,
            'Test files for OATS execution.' ) do |t|
            options['execution:test_files'] = t
          end
          opts.on( '-b', '--browser_type TYPE', ['firefox', 'iexplore','chrome'],
            'Select test execution browser type (firefox, iexplore, chrome)' ) do |t|
            options['selenium:browser_type'] = t
          end
          opts.on( '-e', '--environments env1,env2,env3', Array,
            'Environment list for OATS execution.' ) do |t|
            options['execution:environments'] = t
          end
          opts.on( '-t', '--test_dir DIR_TESTS',
            'Test directory to override environment variable OATS_TESTS.' ) do |t|
            options['_:dir_tests'] = t
          end
          opts.on( '-i', '--ini INI_YAML_FILE',
            'The oats-user.yml to use.' ) do |t|
            options['_:ini_file'] = t
          end
          opts.on( '-p', '--port PORT', Integer,
            'Port number for the Oats Agent.' ) do |t|
            options['execution:occ:agent_port'] = t if t
          end
          opts.on( '-n', '--nickname NICKNAME',
            'Nickname to display on OCC for the Oats Agent.' ) do |t|
            options['execution:occ:agent_nickname'] = t if t
          end
          opts.on( '-o', '--options key11.key12.key13:val1,key21.key22:val2,...', Array,
            'Options to override values specified in oats.yml as well as other commandline options.' ) do |t|
            options['_:options'] = t
          end
          opts.on( '-j', '--json JSON',
            'The json hash to merge with oats data.' ) do |t|
            options['_:json'] = t
          end
          opts.on( '-q', '--quiet',
            'Do not echo anything to the console while running.' ) do |t|
            options['_:quiet'] = true
          end

          # AGENT OPTIONS ONLY
          opts.on( '-a', '--agent',
            'Invokes background agent handling.' ) do |t|
            options['_:agent'] = true
          end
          opts.on( '-u', '--oats_user OATS_USER',
            'Sets OATS_USER for agent, used in conjunction with -a.' ) do |t|
            options['_:oats_user'] = t
          end
          opts.on( '-k', '--kill_agent',
            'Kills the agent, used in conjunction with -a.' ) do |t|
            options['_:kill_agent'] = true
          end
          opts.on( '-r', '--repository',
            'Sets REPOSITORY for agent, used in conjunction with -a.' ) do |t|
            options['_:repository'] = true
          end


          # Development options
          opts.on( '-g', '--gemfile GEMFILE',
            'Gemfile path to be included.' ) do |t|
            options['_:gemfile'] = t
          end
          opts.on( '-d' , '--d_options unit_test_dir1,unit_test_dir2', Array,
            'NetBeans passes these d options to TestUnit.' ) do |t|
            options['_:d_options'] = t
          end
          #        opts.on( '-s', '--show_result_ide TYPE', [ '0', '1', '2'],
          #          'Select the trigger level to show TestRunner results (0, 1, 2) for (On failure, Never, Always)' ) do |t|
          #          options['execution:ide:show_result'] = t.to_f
          #        end
          #        opts.on( '--log_level_console LEVEL',["DEBUG", "INFO", "WARN", "ERROR", "FATAL"],
          #          'Select logging level ("DEBUG", "INFO", "WARN", "ERROR", "FATAL")' ) do |t|
          #          options['execution:log_level_console'] = t
          #        end
          #        opts.on( '-r', '--restrict t1,t2,t3,...', Array,
          #          'Restrict test list execution to the listed tests. NOT FULLY IMPLEMENTED YET.' ) do |t|
          #          options['execution:restrict_tests'] = t
          #        end
          #        opts.on( '-c', '--command COMMAND_STRING',
          #          'Command issued by the client.' ) do |t|
          #          options['_:command'] = t
          #        end
          opts.on_tail( '-h', '--help', 'Display this screen' ) { $stderr.puts opts; exit }
        end

        optparse.parse!(argv)
        if argv and ! argv.empty?
          options['execution:test_files'] ||= []
          options['execution:test_files'] += argv
        end

      rescue Exception => e
        raise unless e.class.to_s =~ /^OptionParser::/
        $stderr.puts e.message
        $stderr.puts "Please type 'oats -h' for valid options."
        exit 1
      end
      options['_:args'] = argv_save
      @@OPTIONS = options
    end

  end
end
