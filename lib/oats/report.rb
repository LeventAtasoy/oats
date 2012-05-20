#require 'oats/oselenium' if $oats_execution
require 'yaml' # http://www.ruby-doc.org/core/classes/YAML.html http://yaml4r.sourceforge.net/doc
require 'oats/test_case'
require 'oats/test_list'
require 'oats/oats_exceptions'

class OatsReportError < OatsError ; end

module Oats

  class Report
    @@pre_test = nil
    @@post_test = nil

    def Report.failed_file_name(var)
      if var.instance_of?(Variation)
        list_name = var.list_name
      else
        list_name = var
      end
      return unless list_name
      return File.basename(list_name) + '.yml' if list_name =~ /-fail$/
      #    File.basename(list_name) + '-ft-' + var.env_name[0,1] + var.env_name[-1,1] + '.yml'
      File.basename(list_name.sub(/\.yml\z/,'')) + '-fail.yml'
    end

    def Report.results(list, from_agent = nil) #
      unless list
        $log.error "Report.results are requested for a null list. Ignoring request."
        return nil
      end
      vars = list.variations
      vars.each do |var|
        tests = []
        var.tests.each do |tst|
          if tst.instance_of?(TestList)
            @@pre_test ||= list.pre_test
            @@post_test ||= list.post_test
            Report.results(tst, from_agent)
          else
            tests << tst
          end
        end
        unless tests.empty?
          if var.parent.id
            list_name = File.basename(var.parent.id,'.*')
          else
            list_name = tests.first.id
          end
          var.list_name = list_name
          dir_results = $oats['execution']['dir_results']
          all_errors = tests.find_all{|i| not i.errors.empty?}
          var.total = tests.length
          var.pass = tests.find_all{|i| i.status == 0}.length
          var.fail = all_errors.length
          var.skip = tests.find_all{|i| i.status == 2}.length
          $log.error "Test counts do not add up. Please report this to the OATS administrator." \
            unless var.total == var.pass + var.fail + var.skip
          pre_post_summary = ''
          unless tests.empty? or from_agent
            if @@pre_test and ! @@pre_test.errors.empty?
              pre_post_summary += ", PRE_FAILURE"
              var.fail += 1
              #        var.fail = var.fail ? (var.fail + 1) : 1
            end
            if @@post_test and ! @@post_test.errors.empty?
              pre_post_summary += ", POST_FAILURE"
              var.fail += 1
            end
            $log.info  "*** SUMMARY STATISTICS for list:#{list_name} on env:#{var.env_name}" +
              " Total[#{var.total}], " + "Fail[#{var.fail}], Pass[#{var.pass}], " + "Skip[#{var.skip}]" +
              pre_post_summary
          end
          return true if all_errors.empty? or from_agent
          # Generate the failed tests lists only for non-agent mode
          failed_file_name = Report.failed_file_name(var)
          failed_dir = Oats.result_archive_dir + '/failed'
          FileUtils.mkdir_p(failed_dir)
          failed_tests_file = File.join(failed_dir,failed_file_name)
          File.open( failed_tests_file, 'w' ) do |ftf |
            ftf.puts("# Failed OATS tests\n---\nexecution: \n  test_files: ")
            tests.each do |test|
              case test.status
              when 0
                $log.error "Unexpected test state for [#{test.id}]. Test status is PASSED but it contains error info. Please report this to the OATS administrator." unless test.errors.empty?
              when 1
                $log.warn "- #{test.id}"
                ftf.puts("    - #{test.id}")
                if test.errors.empty?
                  $log.error "Unexpected test state. Test status is error but it contains no error info. Please report this to the OATS administrator."
                else
                  test.errors.each do |ex_arr|
                    if ex_arr[1] =~ /see result file for details: *(.*)/
                      file = $1
                      $log.warn "  #{file}"
                      ftf.puts "#      #{file}"
                    else
                      exc = "[#{ex_arr[0]}] "  + ex_arr[1]
                      $log.warn "  #{exc}"
                      ftf.puts "#      #{exc}"
                    end
                  end
                end
              when 2 then # Just skipped
                $log.warn "- #{test.id}"
                $log.warn "  [SKIPPED]"
              else
                $log.error "Unknown test status for [#{test.id}]. Please report this to the OATS administrator."
              end
            end
          end
          FileUtils.cp(failed_tests_file,dir_results)
          FileUtils.cp(failed_tests_file,File.join(failed_dir,'last-fail.yml'))
        end
      end
      return true
    end

    # Ideally oats_info_store should use locks and be interrupt safe
    # If dir is nil or oats_info is given dump oats_info, otherwise load and return Report:@@oats_info
    # Default dir is dir_results, default oats_info is $oats_info
    def Report.oats_info_store(dir = nil, oats_info = nil)
      results_file = File.join( dir ? dir : $oats['execution']['dir_results'] , 'results.dump')
      unless dir.nil? or oats_info
        @@oats_info = File.exists?(results_file) ? Report.oats_info_retrieve(results_file) : nil
        return @@oats_info
      end
      archive_dir = Oats.result_archive_dir
      if archive_dir and File.directory?(archive_dir)
        results_file_tmp = File.join(archive_dir, 'results.dump') +'.tmp'
      else
        results_file_tmp = results_file +'.tmp'
      end
      oats_info = $oats_info unless oats_info
      File.open( results_file_tmp , 'w' ) { |out| Marshal.dump(oats_info, out, -1) }
      begin # Ensure dump is written completely before being replaced
        rinfo = File.open( results_file_tmp, 'r' ) { |inp| Marshal.load(inp)}
      rescue Exception => exc
        $log.error "Error reading back [#{results_file_tmp}]. Skipping saving the intermediate results."
        $log.error exc
        return oats_info
      end
      OatsAgent::Ragent.snapshot_oats_info(rinfo) if $oats_execution['agent']
      begin
        FileUtils.mv(results_file_tmp, results_file)
      rescue
        $log.error "Error moving [#{results_file_tmp}]. Skipping saving the intermediate results."
        $log.error exc
      end
      return oats_info
    end

    def Report.oats_info_retrieve(results_file)
      raise OatsReportError, "Can not locate [#{results_file}]. Skipping report generation for: #{results_file}" \
        unless File.exist?(results_file)
      begin
        return File.open( results_file, 'r' ) { |inp| Marshal.load(inp)}
      rescue
        $log.error "Error reading [#{results_file}]. Skipping report generation for: #{results_file}"
        raise
      end
    end

    def Report.archive_results(post_run = false)
      oats_data = $oats
      dir_res = oats_data['execution']['dir_results']
      rm_dir_res = post_run ? false : true
      if File.directory?(dir_res) # Copy current results to archive
        begin
          oats_info = Report.oats_info_store(dir_res)
          unless post_run
            return unless oats_info
            unless oats_info['end_time']
              regenerated = true
              $log.info "Generating missing results files for the previous run."
              Report.results(oats_info['test_files'])
              Report.oats_info_store(nil,oats_info)
            end
          end
        rescue Exception => e
          if e.instance_of? OatsReportError
            $log.error 'Encountered: ' + $!.to_s
          else
            $log.error $!
          end
        end
        # If the stored execution doesn't have context, default to the current execution ids inside incomplete
        archive_id = ((oats_info and oats_info['jobid'])||(Oats.context and Oats.context['jobid']))
        if archive_id
          archive_dir = File.join( Oats.result_archive_dir, archive_id.to_s)
          if post_run
            FileUtils.cp_r(dir_res, archive_dir)
          elsif regenerated or ! File.directory?(archive_dir)
            FileUtils.rm_rf archive_dir
            FileUtils.mv(dir_res, archive_dir)
            rm_dir_res = false
          end
        else
          $log.error "Removing results without archiving because can not find any jobid."
          rm_dir_res = true
        end
        FileUtils.rm_rf dir_res if rm_dir_res # Cleanup prior to next run
      end
    end

  end
end