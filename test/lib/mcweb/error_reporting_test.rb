# frozen_string_literal: true

require "test_helper"
require "mcweb/error_reporting"

module Mcweb
  class ErrorReportingTest < ActiveSupport::TestCase
    test "builds a bounded privacy-safe error event" do
      error = RuntimeError.new(
        "provider failed token=super-secret authorization=Bearer-secret " \
          "redis://user:password@example.test customer@example.test"
      )
      error.set_backtrace(
        [
          "C:/Users/private/Projects/mcweb/app/services/payments/example.rb:14",
          "C:/Ruby/internal.rb:2"
        ]
      )

      event = ErrorReporting.build_event(
        error,
        handled: true,
        severity: :warning,
        source: "application",
        context: {
          request_id: "request-1",
          controller: "payments",
          provider: "stripe",
          email: "customer@example.test",
          password: "never-log-this",
          payload: { card: "never-log-this" }
        }
      )

      assert_equal "RuntimeError", event.fetch(:error_class)
      assert_equal true, event.fetch(:handled)
      assert_equal "warning", event.fetch(:severity)
      assert_match(/token=\[FILTERED\]/, event.fetch(:message))
      assert_match(/authorization=\[FILTERED\]/, event.fetch(:message))
      assert_includes event.fetch(:message), "redis://[FILTERED]@example.test"
      refute_includes event.fetch(:message), "customer@example.test"
      assert_equal(
        {
          "controller" => "payments",
          "provider" => "stripe",
          "request_id" => "request-1"
        },
        event.fetch(:context)
      )
      assert_match(/\A[0-9a-f]{64}\z/, event.fetch(:fingerprint))
      refute_includes event.to_json, "super-secret"
      refute_includes event.to_json, "customer@example.test"
      refute_includes event.to_json, "C:/Users/private"
    end

    test "subscriber isolates a failing external adapter" do
      previous = ErrorReporting.adapter
      ErrorReporting.adapter = ->(_event) { raise "adapter token=hidden" }

      assert_nothing_raised do
        ErrorReporting.subscriber.report(
          RuntimeError.new("business failure"),
          handled: false,
          severity: :error,
          context: { request_id: "request-2" },
          source: "test"
        )
      end
    ensure
      ErrorReporting.adapter = previous
    end

    test "custom adapter receives the normalized event" do
      events = []
      previous = ErrorReporting.adapter
      ErrorReporting.adapter = ->(event) { events << event }

      ErrorReporting.deliver(
        ArgumentError.new("bad input"),
        handled: true,
        severity: :info,
        context: { operation_id: "op-123", unknown: "ignored" },
        source: "manual"
      )

      assert_equal 1, events.length
      assert_equal "ArgumentError", events.first.fetch(:error_class)
      assert_equal(
        { "operation_id" => "op-123" },
        events.first.fetch(:context)
      )
    ensure
      ErrorReporting.adapter = previous
    end
  end
end
