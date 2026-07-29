# frozen_string_literal: true

require "json"
require "optparse"

require_relative "builder"
require_relative "contract_tester"
require_relative "creator"
require_relative "health_checker"
require_relative "releaser"
require_relative "report"
require_relative "validator"

module Mcweb
  module Plugins
    module Devtools
      class Command
        COMMANDS = %w[create validate test build release health].freeze

        def self.run(argv, out: $stdout, err: $stderr)
          new(argv:, out:, err:).run
        end

        def initialize(argv:, out:, err:)
          @argv = Array(argv).dup
          @out = out
          @err = err
          @json = @argv.delete("--json")
        end

        def run
          requested = @argv.shift.to_s.delete_prefix("plugin:")
          if requested.in?(%w[help --help -h]) || requested.empty?
            return emit(help_report, status: requested.empty? ? 2 : 0)
          end
          unless COMMANDS.include?(requested)
            return emit(
              usage_failure("unknown_command", "unknown plugin command #{requested.inspect}"),
              status: 2
            )
          end

          report = send("run_#{requested}")
          emit(report, status: report.ok? ? 0 : 1)
        rescue OptionParser::ParseError, ArgumentError => e
          emit(usage_failure("invalid_arguments", e.message), status: 2)
        rescue StandardError => e
          emit(
            Report.failure(
              "plugin:#{requested.presence || 'unknown'}",
              errors: [ {
                code: "command_failed",
                message: "plugin command could not complete",
                details: { error_class: e.class.name }
              } ]
            ),
            status: 1
          )
        end

        private

        def run_create
          options = {
            root: Pathname.pwd,
            name: nil,
            author: nil
          }
          parser = OptionParser.new do |opts|
            opts.on("--root PATH") { |value| options[:root] = value }
            opts.on("--name NAME") { |value| options[:name] = value }
            opts.on("--author NAME") { |value| options[:author] = value }
          end
          parser.parse!(@argv)
          plugin_id = required_argument!("PLUGIN_ID")
          reject_extra_arguments!
          Creator.new(plugin_id:, **options).call
        end

        def run_validate
          options = { plugins_root: nil, target_api_version: nil }
          parser = OptionParser.new do |opts|
            opts.on("--plugins-root PATH") { |value| options[:plugins_root] = value }
            opts.on("--target-api VERSION") { |value| options[:target_api_version] = value }
          end
          parser.parse!(@argv)
          path = required_argument!("PATH")
          reject_extra_arguments!
          Validator.new(path:, **options).call
        end

        def run_test
          options = { run_plugin_tests: true }
          parser = OptionParser.new do |opts|
            opts.on("--skip-plugin-tests") { options[:run_plugin_tests] = false }
          end
          parser.parse!(@argv)
          path = required_argument!("PATH")
          reject_extra_arguments!
          ContractTester.new(path:, **options).call
        end

        def run_build
          options = { output: nil, include_tests: true }
          parser = OptionParser.new do |opts|
            opts.on("--output PATH") { |value| options[:output] = value }
            opts.on("--without-tests") { options[:include_tests] = false }
          end
          parser.parse!(@argv)
          path = required_argument!("PATH")
          reject_extra_arguments!
          Builder.new(path:, **options).call
        end

        def run_release
          options = { output: nil, include_tests: true }
          parser = OptionParser.new do |opts|
            opts.on("--output PATH") { |value| options[:output] = value }
            opts.on("--without-tests") { options[:include_tests] = false }
          end
          parser.parse!(@argv)
          path = required_argument!("PATH")
          reject_extra_arguments!
          Releaser.new(path:, **options).call
        end

        def run_health
          options = { installed: false }
          parser = OptionParser.new do |opts|
            opts.on("--installed") { options[:installed] = true }
          end
          parser.parse!(@argv)
          target = required_argument!("PATH_OR_PLUGIN_ID")
          reject_extra_arguments!
          HealthChecker.new(target:, **options).call
        end

        def required_argument!(name)
          value = @argv.shift
          raise ArgumentError, "#{name} is required" if value.to_s.empty?

          value
        end

        def reject_extra_arguments!
          return if @argv.empty?

          raise ArgumentError, "unexpected arguments: #{@argv.join(' ')}"
        end

        def usage_failure(code, message)
          Report.failure(
            "plugin:command",
            data: { usage: usage_lines },
            errors: [ { code:, message:, details: {} } ]
          )
        end

        def help_report
          Report.success(
            "plugin:help",
            data: {
              tool_version: Devtools::TOOL_VERSION,
              commands: COMMANDS.map { |command| "plugin:#{command}" },
              usage: usage_lines
            }
          )
        end

        def usage_lines
          [
            "bin/mcweb-plugin create PLUGIN_ID [--root PATH] [--name NAME] [--author NAME] [--json]",
            "bin/mcweb-plugin validate PATH [--plugins-root PATH] [--target-api VERSION] [--json]",
            "bin/mcweb-plugin test PATH [--skip-plugin-tests] [--json]",
            "bin/mcweb-plugin build PATH [--output PATH] [--without-tests] [--json]",
            "bin/mcweb-plugin release PATH [--output PATH] [--without-tests] [--json]",
            "bin/mcweb-plugin health PATH_OR_PLUGIN_ID [--installed] [--json]"
          ].freeze
        end

        def emit(report, status:)
          if @json
            @out.puts(JSON.pretty_generate(report.to_h))
          else
            stream = report.ok? ? @out : @err
            stream.puts("#{report.ok? ? 'OK' : 'FAILED'} #{report.command}")
            report.data.each do |key, value|
              next if value.is_a?(Hash) || value.is_a?(Array)

              stream.puts("#{key}: #{value}")
            end
            report.warnings.each { |warning| stream.puts("warning: #{warning.fetch('message')}") }
            report.errors.each { |error| stream.puts("error: #{error.fetch('message')}") }
            usage = report.data["usage"]
            stream.puts(usage.join("\n")) if usage
          end
          status
        end
      end
    end
  end
end
