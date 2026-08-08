# frozen_string_literal: true

require "test_helper"

class Mcweb::RequestPerformanceMiddlewareTest < ActiveSupport::TestCase
  test "reports queue middleware and total timings without exposing request data" do
    monotonic_values = [ 10.0, 10.1 ]
    event_payload = nil
    subscriber = ActiveSupport::Notifications.subscribe(
      "mcweb.request.outer"
    ) do |event|
      event_payload = event.payload
    end
    app = lambda do |_environment|
      ActiveSupport::IsolatedExecutionState[
        Mcweb::RequestPerformanceMiddleware::ACTION_DURATION_KEY
      ] = 20.0
      [ 200, { "Server-Timing" => "sql;dur=4" }, [ "ok" ] ]
    end
    middleware = Mcweb::RequestPerformanceMiddleware.new(
      app,
      monotonic_clock: -> { monotonic_values.shift },
      wall_clock: -> { 1_000.0 }
    )

    status, headers, body = middleware.call(
      "PATH_INFO" => "/admin/users?token=secret",
      "HTTP_X_REQUEST_START" => "t=999.95"
    )

    assert_equal 200, status
    assert_equal [ "ok" ], body
    assert_includes headers.fetch("Server-Timing"), "sql;dur=4"
    assert_includes headers.fetch("Server-Timing"), "queue;dur=50.0"
    assert_includes headers.fetch("Server-Timing"), "middleware;dur=80.0"
    assert_includes headers.fetch("Server-Timing"), "rack;dur=100.0"
    assert_includes headers.fetch("Server-Timing"), "total;dur=150.0"
    assert_equal "admin", event_payload.fetch(:surface)
    assert_equal 50.0, event_payload.fetch(:queue_duration_ms)
    assert_equal 100.0, event_payload.fetch(:rack_duration_ms)
    assert_equal 150.0, event_payload.fetch(:duration_ms)
    refute_includes event_payload.to_json, "token"
    assert_nil ActiveSupport::IsolatedExecutionState[
      Mcweb::RequestPerformanceMiddleware::ACTION_DURATION_KEY
    ]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  test "ignores malformed and implausibly old queue headers" do
    values = [ 1.0, 1.01, 2.0, 2.01 ]
    middleware = Mcweb::RequestPerformanceMiddleware.new(
      ->(_environment) { [ 204, {}, [] ] },
      monotonic_clock: -> { values.shift },
      wall_clock: -> { 2_000.0 }
    )

    _status, malformed_headers, = middleware.call(
      "PATH_INFO" => "/up",
      "HTTP_X_REQUEST_START" => "not-a-time"
    )
    _status, stale_headers, = middleware.call(
      "PATH_INFO" => "/up",
      "HTTP_X_REQUEST_START" => "1"
    )

    refute_includes malformed_headers.fetch("Server-Timing"), "queue;"
    refute_includes stale_headers.fetch("Server-Timing"), "queue;"
  end
end
