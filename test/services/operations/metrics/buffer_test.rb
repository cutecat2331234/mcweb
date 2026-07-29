# frozen_string_literal: true

require "test_helper"

module Operations
  module Metrics
    class BufferTest < ActiveSupport::TestCase
      test "concurrent samples aggregate into one bounded minute entry" do
        now = Time.zone.parse("2026-07-29 15:00:30")
        written = []
        buffer = Buffer.new(
          max_keys: 8,
          clock: -> { now },
          writer: ->(entries) { written.concat(entries) }
        )

        threads = 8.times.map do
          Thread.new do
            100.times do
              buffer.record(
                "request.duration_ms",
                value: 2,
                dimensions: {
                  surface: "admin",
                  outcome: "success"
                },
                at: now
              )
            end
          end
        end
        threads.each(&:join)

        assert_equal 800, buffer.flush!(now:)
        assert_equal 1, written.length
        entry = written.first
        assert_equal 800, entry.fetch(:sample_count)
        assert_equal 1_600.to_d, entry.fetch(:value_sum)
        assert_equal 2.to_d, entry.fetch(:value_min)
        assert_equal 2.to_d, entry.fetch(:value_max)
      end

      test "failed flush restores the batch and merges samples recorded later" do
        now = Time.zone.parse("2026-07-29 15:00:30")
        attempts = 0
        written = []
        buffer = Buffer.new(
          clock: -> { now },
          writer: lambda do |entries|
            attempts += 1
            raise ActiveRecord::ConnectionNotEstablished if attempts == 1

            written.concat(entries)
          end
        )
        dimensions = { queue: "maintenance", outcome: "failure" }

        buffer.record(
          "job.execution.duration_ms",
          value: 50,
          dimensions:,
          at: now
        )
        assert_equal false, buffer.flush!(now:)
        assert_equal 1, buffer.pending_samples

        buffer.record(
          "job.execution.duration_ms",
          value: 150,
          dimensions:,
          at: now
        )
        assert_equal 2, buffer.flush!(now:)

        entry = written.fetch(0)
        assert_equal 2, entry.fetch(:sample_count)
        assert_equal 200.to_d, entry.fetch(:value_sum)
        assert_equal 50.to_d, entry.fetch(:value_min)
        assert_equal 150.to_d, entry.fetch(:value_max)
      end

      test "first sample after the minute boundary flushes the prior bucket" do
        first_minute = Time.zone.parse("2026-07-29 15:00:30")
        current_time = first_minute
        written = []
        buffer = Buffer.new(
          clock: -> { current_time },
          writer: ->(entries) { written.concat(entries) }
        )

        buffer.record("queue.enqueued", value: 4, at: first_minute)
        current_time = first_minute + 1.minute
        buffer.record("queue.enqueued", value: 6, at: current_time)

        assert_equal 1, written.length
        assert_equal first_minute.change(sec: 0),
          written.first.fetch(:bucket_at)
        assert_equal 4.to_d, written.first.fetch(:value_sum)
        assert_equal 1, buffer.pending_samples
      end

      test "buffer drops new cardinality after its hard key bound" do
        now = Time.zone.parse("2026-07-29 15:00:30")
        buffer = Buffer.new(
          max_keys: 1,
          clock: -> { now },
          writer: ->(_entries) { }
        )

        assert buffer.record(
          "request.duration_ms",
          dimensions: { surface: "admin", outcome: "success" },
          at: now
        )
        assert_not buffer.record(
          "request.duration_ms",
          dimensions: { surface: "api", outcome: "success" },
          at: now
        )
        assert_equal 1, buffer.size
        assert_equal 1, buffer.dropped_samples
      end
    end
  end
end
