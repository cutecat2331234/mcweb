# frozen_string_literal: true

require_relative "../marketplace"
require_relative "contract_tester"
require_relative "report"
require_relative "validator"

module Mcweb
  module Plugins
    module Devtools
      class HealthChecker
        def initialize(target:, installed: false)
          @target = target
          @installed = installed
        end

        def call
          @installed ? installed_health : source_health
        rescue Error, ManifestError, Marketplace::Error => e
          Report.failure(
            "plugin:health",
            errors: [ {
              code: e.respond_to?(:code) ? e.code : "health_check_failed",
              message: e.message,
              details: e.respond_to?(:details) ? e.details : {}
            } ]
          )
        rescue StandardError => e
          Report.failure(
            "plugin:health",
            errors: [ {
              code: "health_check_failed",
              message: "plugin health check could not complete",
              details: { error_class: e.class.name }
            } ]
          )
        end

        private

        def source_health
          validation = Validator.new(path: @target).call
          contract = ContractTester.new(path: @target, run_plugin_tests: false).call
          errors = validation.errors + contract.errors
          warnings = validation.warnings + contract.warnings
          data = {
            mode: "source",
            path: Pathname(@target).expand_path.to_s,
            validation: validation.to_h,
            runtime: contract.data["contract_checks"]
          }
          if errors.empty?
            Report.success("plugin:health", data:, warnings:)
          else
            Report.failure("plugin:health", data:, warnings:, errors:)
          end
        end

        def installed_health
          manager = Marketplace.manager
          file_health = manager.health(plugin_id: @target)
          status = manager.status(plugin_id: @target)
          plugin = status.fetch(:plugins).first
          errors = status.fetch(:errors).dup
          unless plugin
            errors << {
              code: "plugin_not_installed",
              message: "installed plugin was not found",
              details: { plugin_id: @target }
            }
          end
          if file_health[:status] != "healthy"
            errors << {
              code: "installed_files_unhealthy",
              message: "installed plugin files are not healthy",
              details: file_health
            }
          end
          runtime_status = plugin&.fetch(:runtime_status, nil)
          if plugin && !runtime_status.in?(%w[active degraded])
            errors << {
              code: "runtime_not_active",
              message: "installed plugin is not active in this process",
              details: { runtime_status: }
            }
          end

          data = {
            mode: "installed",
            plugin:,
            file_health:,
            operations: status.fetch(:operations)
          }
          if errors.empty?
            Report.success("plugin:health", data:)
          else
            Report.failure("plugin:health", data:, errors:)
          end
        end
      end
    end
  end
end
