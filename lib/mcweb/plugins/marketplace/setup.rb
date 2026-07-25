# frozen_string_literal: true

require "pathname"
require "rubygems"
require "set"
require "time"
require_relative "error"

module Mcweb
  module Plugins
    module Marketplace
      module Setup
        SCHEMA_VERSION = "1"
        MAX_STEPS = 1_000
        MAX_PERSISTED_STEPS = 10_000
        STEP_ID_PATTERN = /\A[a-z][a-z0-9_.-]{0,127}\z/
        PHASES = %w[install upgrade uninstall].freeze
        REGISTRATION_THREAD_KEY = :mcweb_marketplace_setup_registration

        Step = Data.define(:id, :phase, :target_version, :target_version_object, :sequence, :callback)

        class Context
          attr_reader :plugin_id, :phase, :step_id, :from_version, :to_version,
                      :target_version, :operation_id, :connection

          def initialize(plugin_id:, phase:, step_id:, from_version:, to_version:,
                         target_version:, operation_id:, connection:)
            @plugin_id = plugin_id.to_s.dup.freeze
            @phase = phase.to_s.dup.freeze
            @step_id = step_id.to_s.dup.freeze
            @from_version = immutable_optional_string(from_version)
            @to_version = immutable_optional_string(to_version)
            @target_version = immutable_optional_string(target_version)
            @operation_id = operation_id.to_s.dup.freeze
            @connection = connection
            freeze
          end

          private

          def immutable_optional_string(value)
            value.nil? ? nil : value.to_s.dup.freeze
          end
        end

        class Plan
          attr_reader :plugin_id, :package_version, :steps

          def initialize(plugin_id:, package_version:, steps:)
            @plugin_id = plugin_id.to_s.dup.freeze
            @package_version = package_version.to_s.dup.freeze
            @steps = steps.freeze
            freeze
          end

          def steps_for(phase:, from_version: nil, to_version: nil)
            phase = phase.to_s
            selected = steps.select { |step| step.phase == phase }
            return selected.sort_by(&:sequence).freeze unless phase == "upgrade"
            return [].freeze if from_version.nil? || to_version.nil?

            from = Gem::Version.new(from_version)
            to = Gem::Version.new(to_version)
            return [].freeze unless to > from

            selected.select do |step|
              step.target_version_object > from && step.target_version_object <= to
            end.sort_by { |step| [ step.target_version_object, step.sequence ] }.freeze
          end
        end

        class Builder
          def initialize(plugin_id:, package_version:)
            @plugin_id = plugin_id
            @package_version = package_version
            @package_version_object = Gem::Version.new(package_version)
            @steps = []
            @step_ids = Set.new
          end

          def install_step(id, &callback)
            add_step(:install, id, callback:)
          end

          def upgrade_step(id, to:, &callback)
            target_version = normalize_version(to)
            if Gem::Version.new(target_version) > @package_version_object
              raise SetupError, "upgrade step target cannot exceed the package version"
            end

            add_step(:upgrade, id, target_version:, callback:)
          end

          def uninstall_step(id, &callback)
            add_step(:uninstall, id, callback:)
          end

          alias_method :teardown_step, :uninstall_step

          def build
            Plan.new(plugin_id: @plugin_id, package_version: @package_version, steps: @steps.dup)
          end

          private

          def add_step(phase, raw_id, target_version: nil, callback:)
            raise SetupError, "plugin setup has too many steps" if @steps.length >= MAX_STEPS
            raise SetupError, "plugin setup steps require a block" unless callback

            id = raw_id.to_s
            raise SetupError, "invalid plugin setup step id" unless id.match?(STEP_ID_PATTERN)
            raise SetupError, "duplicate plugin setup step id #{id}" unless @step_ids.add?(id)

            @steps << Step.new(
              id: id.dup.freeze,
              phase: phase.to_s.freeze,
              target_version: target_version,
              target_version_object: target_version && Gem::Version.new(target_version),
              sequence: @steps.length,
              callback: callback
            )
            self
          end

          def normalize_version(value)
            version = value.to_s
            unless version.match?(Mcweb::Plugins::Manifest::SEMVER_PATTERN)
              raise SetupError, "upgrade step target must be SemVer"
            end

            version.dup.freeze
          end
        end

        class Registration
          def initialize(plugin_id:, package_version:)
            @plugin_id = plugin_id
            @package_version = package_version
          end

          def define(&definition)
            raise SetupError, "plugin setup must register exactly one plan" if @plan
            raise SetupError, "plugin setup definition requires a block" unless definition

            builder = Builder.new(plugin_id: @plugin_id, package_version: @package_version)
            if definition.arity.zero?
              builder.instance_exec(&definition)
            else
              definition.call(builder)
            end
            @plan = builder.build
          end

          def plan!
            @plan || raise(SetupError, "plugin setup must register exactly one plan")
          end
        end

        class State
          attr_reader :completed_version, :completed_steps

          def self.empty
            new(completed_version: nil, completed_steps: [])
          end

          def self.load(value)
            return empty if value.nil?
            raise SetupError, "invalid persisted plugin setup state" unless value.is_a?(Hash)

            data = value.transform_keys(&:to_s)
            allowed_keys = %w[schema_version completed_version completed_steps]
            unless (data.keys - allowed_keys).empty? && data["schema_version"] == SCHEMA_VERSION
              raise SetupError, "invalid persisted plugin setup state"
            end

            completed_version = data["completed_version"]
            validate_version!(completed_version) if completed_version
            raw_steps = data.fetch("completed_steps", [])
            unless raw_steps.is_a?(Array) && raw_steps.length <= MAX_PERSISTED_STEPS
              raise SetupError, "invalid persisted plugin setup state"
            end

            steps = raw_steps.map { |step| normalize_record(step) }
            ids = steps.pluck("id")
            raise SetupError, "invalid persisted plugin setup state" unless ids.uniq.length == ids.length

            new(completed_version:, completed_steps: steps)
          rescue SetupError
            raise
          rescue StandardError
            raise SetupError, "invalid persisted plugin setup state"
          end

          def self.normalize_record(value)
            raise SetupError, "invalid persisted plugin setup state" unless value.is_a?(Hash)

            record = value.transform_keys(&:to_s)
            required = %w[id phase completed_at operation_id]
            allowed = required + %w[target_version]
            unless (record.keys - allowed).empty? && required.all? { |key| record[key].is_a?(String) }
              raise SetupError, "invalid persisted plugin setup state"
            end
            unless record["id"].match?(STEP_ID_PATTERN) && PHASES.include?(record["phase"])
              raise SetupError, "invalid persisted plugin setup state"
            end
            validate_version!(record["target_version"]) if record["target_version"]
            unless record["completed_at"].length <= 128 && record["operation_id"].length.between?(1, 191)
              raise SetupError, "invalid persisted plugin setup state"
            end
            Time.iso8601(record["completed_at"])

            record.transform_values { |item| item.is_a?(String) ? item.dup.freeze : item }.freeze
          end
          private_class_method :normalize_record

          def self.validate_version!(version)
            unless version.is_a?(String) &&
                   version.length <= Mcweb::Plugins::Manifest::MAX_VERSION_LENGTH &&
                   version.match?(Mcweb::Plugins::Manifest::SEMVER_PATTERN)
              raise SetupError, "invalid persisted plugin setup state"
            end
          end
          private_class_method :validate_version!

          def initialize(completed_version:, completed_steps:)
            @completed_version = completed_version&.dup&.freeze
            @completed_steps = completed_steps.dup.freeze
            @completed_ids = @completed_steps.pluck("id").to_set.freeze
            freeze
          end

          def completed?(step_id)
            @completed_ids.include?(step_id)
          end

          def completed_record(step_id)
            completed_steps.find { |record| record["id"] == step_id }
          end

          def append(records, completed_version:)
            State.new(
              completed_version: greatest_version(self.completed_version, completed_version),
              completed_steps: completed_steps + records
            )
          end

          def to_h
            {
              "schema_version" => SCHEMA_VERSION,
              "completed_version" => completed_version,
              "completed_steps" => completed_steps
            }.freeze
          end

          private

          def greatest_version(left, right)
            return left unless right
            return right unless left

            Gem::Version.new(left) >= Gem::Version.new(right) ? left : right
          end
        end

        class << self
          def define(&definition)
            registration = Thread.current.thread_variable_get(REGISTRATION_THREAD_KEY)
            raise SetupError, "plugin setup registration is not active" unless registration

            registration.define(&definition)
          end

          def load_file(path, plugin_id:, package_version:)
            path = Pathname(path)
            raise SetupError, "plugin setup file is unavailable" unless path.file?

            previous = Thread.current.thread_variable_get(REGISTRATION_THREAD_KEY)
            raise SetupError, "nested plugin setup registration is not allowed" if previous

            registration = Registration.new(plugin_id:, package_version:)
            begin
              Thread.current.thread_variable_set(REGISTRATION_THREAD_KEY, registration)
              Kernel.load(path.to_s)
              registration.plan!
            rescue SetupError
              raise
            rescue StandardError, ScriptError => error
              raise SetupError, "plugin setup registration failed (#{safe_error_class(error)})"
            ensure
              Thread.current.thread_variable_set(REGISTRATION_THREAD_KEY, previous)
            end
          end

          def execute(plan:, phase:, state:, plugin_id:, from_version:, to_version:,
                      operation_id:, connection:, clock:)
            records = []
            plan.steps_for(phase:, from_version:, to_version:).each do |step|
              if (completed = state.completed_record(step.id))
                same_step = completed["phase"] == phase.to_s &&
                            completed["target_version"] == step.target_version
                unless same_step
                  raise SetupError, "completed plugin setup step id conflicts with the current plan"
                end
                next
              end

              context = Context.new(
                plugin_id:,
                phase:,
                step_id: step.id,
                from_version:,
                to_version:,
                target_version: step.target_version,
                operation_id:,
                connection:
              )
              begin
                step.callback.call(context)
              rescue StandardError, ScriptError => error
                raise SetupExecutionError.new(
                  phase: phase,
                  step_id: step.id,
                  error_class: safe_error_class(error)
                )
              end
              records << {
                "id" => step.id,
                "phase" => phase.to_s,
                "target_version" => step.target_version,
                "completed_at" => clock.call.utc.iso8601(6),
                "operation_id" => operation_id.to_s
              }.compact.transform_values { |value| value.dup.freeze }.freeze
            end

            completed_version = %i[install upgrade].include?(phase.to_sym) ? to_version : nil
            state.append(records, completed_version:)
          end

          private

          def safe_error_class(error)
            name = error.class.name.to_s
            name = "RuntimeError" unless name.match?(/\A[A-Za-z][A-Za-z0-9_:]{0,190}\z/)
            name
          end
        end
      end
    end
  end
end
