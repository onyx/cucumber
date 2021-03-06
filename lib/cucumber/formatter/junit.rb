require 'cucumber/formatter/ordered_xml_markup'

module Cucumber
  module Formatter
    # The formatter used for <tt>--format junit</tt>
    class Junit
      def initialize(step_mother, io, options)
        raise "You *must* specify --out DIR for the junit formatter" unless String === io && File.directory?(io)
        @reportdir = io
        @options = options
      end

      def before_feature(feature)
        @failures = @errors = @tests = 0
        @builder = OrderedXmlMarkup.new( :indent => 2 )
        @time = 0
      end
      
      def after_feature(feature)
        @testsuite = OrderedXmlMarkup.new( :indent => 2 )
        @testsuite.instruct!
        @testsuite.testsuite(
          :failures => @failures,
          :errors => @errors,
          :tests => @tests,
          :time => "%.6f" % @time,
          :name => @feature_name ) do
          @testsuite << @builder.target!
        end

        write_file(feature_result_filename(feature.file), @testsuite.target!)
      end

      def before_background(*args)
        @in_background = true
      end
      
      def after_background(*args)
        @in_background = false
      end

      def feature_name(name)
        lines = name.split(/\r?\n/)
        @feature_name = lines[0].sub(/Feature\:/, '').strip
      end

      def scenario_name(keyword, name, file_colon_line, source_indent)
        scenario_name = name.strip.delete(".\r\n")
        scenario_name = "Unnamed scenario" if name.blank?
        @scenario = scenario_name
        @outline = keyword.include?('Scenario Outline')
        @output = "Scenario#{ " outline" if @outline}: #{@scenario}\n\n"
      end

      def before_steps(steps)
        @steps_start = Time.now
      end
      
      def after_steps(steps)
        return if @in_background || @outline
        
        duration = Time.now - @steps_start
        if steps.failed?
          steps.each { |step| @output += "#{step.keyword} #{step.name}\n" }
          @output += "\nMessage:\n"
        end
        build_testcase(duration, steps.status, steps.exception)
      end
      
      def before_examples(*args)
        @header_row = true
      end

      def before_table_row(table_row)
        return unless @outline

        @table_start = Time.now
      end

      def after_table_row(table_row)
        return unless @outline
        duration = Time.now - @table_start
        unless @header_row
          name_suffix = " (outline example : #{table_row.name})"
          if table_row.failed?
            @output += "Example row: #{table_row.name}\n"
            @output += "\nMessage:\n"
          end
          build_testcase(duration, table_row.status, table_row.exception, name_suffix)
        end
        
        @header_row = false if @header_row
      end

      private

      def build_testcase(duration, status, exception = nil, suffix = "")
        @time += duration
        classname = "#{@feature_name}.#{@scenario}"
        name = "#{@scenario}#{suffix}"
        failed = (status == :failed || (status == :pending && @options[:strict]))
        #puts "FAILED:!!#{failed}"
        if status == :passed || failed
          @builder.testcase(:classname => classname, :name => name, :time => "%.6f" % duration) do
            if failed
              @builder.failure(:message => "#{status.to_s} #{name}", :type => status.to_s) do
                @builder.text! @output
                @builder.text!(format_exception(exception)) if exception
              end
              @failures += 1
            end
          end
          @tests += 1
        end
      end

      def format_exception(exception)
        (["#{exception.message} (#{exception.class})"] + exception.backtrace).join("\n")
      end
      
      def feature_result_filename(feature_file)
        ext_length = File.extname(feature_file).length
        basename = File.basename(feature_file)[0...-ext_length]
        File.join(@reportdir, "TEST-#{basename}.xml")
      end
      
      def write_file(feature_filename, data)
        File.open(feature_filename, 'w') { |file| file.write(data) }
      end
    end
  end
end
