# frozen_string_literal: true

require_relative "../error"

module Mcweb
  module Plugins
    module Marketplace
      class Error < Mcweb::Plugins::Error; end
      class SourceError < Error; end
      class PackageError < Error; end
      class IntegrityError < PackageError; end
      class CompatibilityError < PackageError; end
      class DependencyError < PackageError; end
      class LifecycleError < Error; end
      class SetupError < Error; end

      class SetupExecutionError < SetupError
        attr_reader :phase, :step_id, :error_class

        def initialize(phase:, step_id:, error_class:)
          @phase = phase.to_s.freeze
          @step_id = step_id.to_s.freeze
          @error_class = error_class.to_s.freeze
          super("plugin setup #{phase} step #{step_id} failed (#{error_class})")
        end
      end
    end
  end
end
