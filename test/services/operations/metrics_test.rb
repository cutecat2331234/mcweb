# frozen_string_literal: true

require "test_helper"

class Operations::MetricsTest < ActiveSupport::TestCase
  class MemoryLogger
    attr_reader :warnings

    def initialize
      @warnings = []
    end

    def warn(message)
      @warnings << message
    end
  end

  setup do
    Operations::Metrics.reset!
  end

  test "diagnostic failures include bounded detail and are rate limited" do
    logger = MemoryLogger.new
    error = NameError.new("uninitialized constant Operations::Metrics::Buffer")
    error.set_backtrace([
      Rails.root.join("app/services/operations/metrics.rb:12").to_s,
      Rails.root.join("app/controllers/application_controller.rb:1").to_s,
      "C:/external/gem.rb:2"
    ])

    assert Operations::Metrics.report_failure("sample ignored", error, logger:)
    assert_not Operations::Metrics.report_failure(
      "sample ignored",
      error,
      logger:
    )

    assert_equal 1, logger.warnings.length
    warning = logger.warnings.first
    assert_includes warning, "NameError"
    assert_includes warning, "uninitialized constant"
    assert_includes warning, "app/services/operations/metrics.rb"
    refute_includes warning, "external/gem.rb"
  end

  test "diagnostic failures redact common credential fields" do
    logger = MemoryLogger.new
    error = RuntimeError.new("request failed token=plain-secret password:guess")

    assert Operations::Metrics.report_failure("sample ignored", error, logger:)

    warning = logger.warnings.fetch(0)
    refute_includes warning, "plain-secret"
    refute_includes warning, "guess"
    assert_includes warning, "token=[FILTERED]"
    assert_includes warning, "password=[FILTERED]"
  end

  test "unknown metric keys are ignored without allocating buffer entries" do
    buffer = Operations::Metrics::Buffer.new(
      writer: ->(_entries) { }
    )
    Operations::Metrics.buffer = buffer

    assert_not Operations::Metrics.record(
      "request.dynamic_account_42",
      dimensions: { account_id: 42 }
    )
    assert_equal 0, buffer.size
    assert_equal 0, buffer.dropped_samples
  end
end
