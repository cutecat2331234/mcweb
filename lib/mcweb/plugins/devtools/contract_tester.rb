# frozen_string_literal: true

require "logger"
require "open3"
require "rbconfig"
require "tmpdir"

require_relative "../loader"
require_relative "report"
require_relative "support"
require_relative "validator"

module Mcweb
  module Plugins
    module Devtools
      class ContractTester
        MAX_CAPTURE_BYTES = 64 * 1024
        REALTIME_PATTERN = /
          ActionCable|
          Turbo::StreamsChannel|
          WebSocket|
          websocket|
          ws:\/\/|
          wss:\/\/
        /x
        RUNTIME_EXTENSIONS = %w[.rb .js .jsx .ts .tsx .vue].freeze

        def initialize(path:, run_plugin_tests: true, test_executor: nil)
          @path = path
          @run_plugin_tests = run_plugin_tests
          @test_executor = test_executor || method(:execute_plugin_tests)
        end

        def call
          directory = Support.plugin_directory(@path)
          validation = Validator.new(path: directory).call
          return rebind_failure(validation) unless validation.ok?

          errors = []
          warnings = validation.warnings.dup
          checks = []
          scan_realtime_references(directory, checks, errors)
          exercise_host_lifecycle(directory, checks, errors)
          exercise_plugin_tests(directory, checks, errors, warnings)
          data = validation.data.merge("contract_checks" => checks)

          if errors.empty?
            Report.success("plugin:test", data:, warnings:)
          else
            Report.failure("plugin:test", data:, warnings:, errors:)
          end
        rescue Error, ManifestError => e
          Report.failure(
            "plugin:test",
            errors: [ {
              code: e.respond_to?(:code) ? e.code : "contract_test_failed",
              message: e.message,
              details: e.respond_to?(:details) ? e.details : {}
            } ]
          )
        rescue StandardError => e
          Report.failure(
            "plugin:test",
            errors: [ {
              code: "contract_test_failed",
              message: "plugin contract test could not complete",
              details: { error_class: e.class.name }
            } ]
          )
        ensure
          Mcweb::Plugins.reset!
        end

        private

        def scan_realtime_references(directory, checks, errors)
          matches = directory.glob("**/*").select do |path|
            path.file? && RUNTIME_EXTENSIONS.include?(path.extname.downcase) &&
              path.read(encoding: Encoding::UTF_8).match?(REALTIME_PATTERN)
          rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
            false
          end
          if matches.empty?
            checks << { name: "ce_realtime_boundary", status: "passed" }
            return
          end

          relative = matches.map { |path| path.relative_path_from(directory).to_s.tr("\\", "/") }
          errors << {
            code: "ce_realtime_reference",
            message: "CE plugins must not contain realtime WebSocket runtime code",
            details: { paths: relative.sort }
          }
          checks << { name: "ce_realtime_boundary", status: "failed" }
        end

        def exercise_host_lifecycle(directory, checks, errors)
          manifest = Manifest.load_file(directory.join(Support::MANIFEST_NAME))
          temporary = Pathname(Dir.mktmpdir("mcweb-plugin-contract-"))
          plugin_root = temporary.join("plugins")
          staged = Support.destination_directory(root: plugin_root, plugin_id: manifest.id)
          Support.copy_package_tree(source: directory, destination: staged, include_tests: true)

          Mcweb::Plugins.reload!(root: plugin_root)
          runtime = Mcweb::Plugins.list.find { |entry| entry.fetch(:id) == manifest.id }
          diagnostics = Mcweb::Plugins.diagnostics.select do |entry|
            entry[:plugin_id] == manifest.id && entry[:level] == "error"
          end
          unless runtime && runtime.fetch(:status) == "active" && diagnostics.empty?
            errors << {
              code: "host_activation_failed",
              message: "plugin did not become active in the host registry",
              details: {
                status: runtime&.fetch(:status, nil),
                diagnostic_codes: diagnostics.map { |entry| entry[:code] }.uniq.sort
              }
            }
            checks << { name: "host_lifecycle", status: "failed" }
            return
          end

          contribution_count = Mcweb::Plugins.contributions_for(manifest.id).length
          Mcweb::Plugins.reset!
          absent = Mcweb::Plugins.list.none? { |entry| entry.fetch(:id) == manifest.id }
          unless absent
            errors << {
              code: "host_reset_failed",
              message: "plugin remained registered after host reset",
              details: {}
            }
            checks << { name: "host_lifecycle", status: "failed" }
            return
          end
          checks << {
            name: "host_lifecycle",
            status: "passed",
            contributions: contribution_count
          }
        ensure
          Mcweb::Plugins.reset!
          FileUtils.remove_entry(temporary) if temporary&.exist?
        end

        def exercise_plugin_tests(directory, checks, errors, warnings)
          test_files = directory.glob("test/**/*_test.rb").select(&:file?).sort
          unless @run_plugin_tests
            checks << { name: "plugin_tests", status: "skipped", files: test_files.length }
            return
          end
          if test_files.empty?
            warnings << {
              code: "plugin_tests_missing",
              message: "plugin does not provide test/**/*_test.rb",
              details: {}
            }
            checks << { name: "plugin_tests", status: "not_present", files: 0 }
            return
          end

          outcome = @test_executor.call(test_files)
          checks << {
            name: "plugin_tests",
            status: outcome.fetch(:success) ? "passed" : "failed",
            files: test_files.length,
            exit_status: outcome.fetch(:exit_status)
          }
          return if outcome.fetch(:success)

          errors << {
            code: "plugin_tests_failed",
            message: "plugin-provided tests failed",
            details: {
              exit_status: outcome.fetch(:exit_status),
              output: outcome.fetch(:output).byteslice(0, MAX_CAPTURE_BYTES)
            }
          }
        end

        def execute_plugin_tests(test_files)
          environment = {
            "RAILS_ENV" => "test",
            "PARALLEL_WORKERS" => "1",
            "MCWEB_DEVELOPER_MODE" => "0"
          }
          command = [
            RbConfig.ruby,
            Rails.root.join("bin/rails").to_s,
            "test",
            *test_files.map(&:to_s)
          ]
          stdout, stderr, status = Open3.capture3(environment, *command, chdir: Rails.root.to_s)
          {
            success: status.success?,
            exit_status: status.exitstatus,
            output: [ stdout, stderr ].reject(&:empty?).join("\n")
          }
        end

        def rebind_failure(report)
          Report.failure(
            "plugin:test",
            data: report.data,
            warnings: report.warnings,
            errors: report.errors
          )
        end
      end
    end
  end
end
