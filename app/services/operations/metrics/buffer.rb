# frozen_string_literal: true

module Operations
  module Metrics
    class Buffer
      DEFAULT_MAX_KEYS = Registry::MAX_TOTAL_CARDINALITY
      FLUSH_INTERVAL = 1.minute

      def initialize(
        max_keys: DEFAULT_MAX_KEYS,
        writer: ->(entries) { MetricBucket.atomic_merge!(entries) },
        clock: -> { Time.current }
      )
        @max_keys = [ Integer(max_keys), 1 ].max
        @writer = writer
        @clock = clock
        @mutex = Mutex.new
        @entries = {}
        @dropped_samples = 0
        @next_flush_at = next_minute(@clock.call)
      end

      def record(metric_name, value: 1, dimensions: {}, at: @clock.call)
        flush_if_due!(at)
        normalized = ::Operations::Metrics::Catalog.normalize(
          metric_name,
          value:,
          dimensions:
        )
        bucket_at = minute_bucket(at)
        key = [
          bucket_at.to_i,
          normalized.metric_name,
          normalized.dimensions_key
        ]

        @mutex.synchronize do
          entry = @entries[key]
          if entry
            merge_sample!(entry, normalized.value)
          elsif @entries.length < @max_keys
            @entries[key] = new_entry(bucket_at, normalized)
          else
            @dropped_samples += 1
            return false
          end
        end
        true
      end

      def flush_if_due!(now = @clock.call)
        due = @mutex.synchronize { now >= @next_flush_at }
        flush!(now:) if due
      end

      def flush!(now: @clock.call)
        batch = take_batch(now)
        return 0 if batch.empty?

        @writer.call(batch)
        batch.sum { |entry| entry.fetch(:sample_count) }
      rescue StandardError => error
        restore_batch(batch || [])
        ::Operations::Metrics.report_failure("flush retained for retry", error)
        false
      end

      def size
        @mutex.synchronize { @entries.length }
      end

      def pending_samples
        @mutex.synchronize do
          @entries.values.sum { |entry| entry.fetch(:sample_count) }
        end
      end

      def dropped_samples
        @mutex.synchronize { @dropped_samples }
      end

      private

      def take_batch(now)
        @mutex.synchronize do
          batch = @entries.values
          @entries = {}
          @next_flush_at = next_minute(now)
          batch
        end
      end

      def restore_batch(batch)
        @mutex.synchronize do
          batch.each do |entry|
            key = entry_key(entry)
            if (current = @entries[key])
              merge_entry!(current, entry)
            elsif @entries.length < @max_keys
              @entries[key] = entry
            else
              @dropped_samples += entry.fetch(:sample_count)
            end
          end
        end
      end

      def new_entry(bucket_at, normalized)
        {
          bucket_at:,
          metric_name: normalized.metric_name,
          dimensions: normalized.dimensions,
          dimensions_key: normalized.dimensions_key,
          sample_count: 1,
          value_sum: normalized.value,
          value_min: normalized.value,
          value_max: normalized.value
        }
      end

      def merge_sample!(entry, value)
        entry[:sample_count] += 1
        entry[:value_sum] += value
        entry[:value_min] = value if value < entry[:value_min]
        entry[:value_max] = value if value > entry[:value_max]
      end

      def merge_entry!(target, source)
        target[:sample_count] += source.fetch(:sample_count)
        target[:value_sum] += source.fetch(:value_sum)
        target[:value_min] = [
          target.fetch(:value_min),
          source.fetch(:value_min)
        ].min
        target[:value_max] = [
          target.fetch(:value_max),
          source.fetch(:value_max)
        ].max
      end

      def entry_key(entry)
        [
          entry.fetch(:bucket_at).to_i,
          entry.fetch(:metric_name),
          entry.fetch(:dimensions_key)
        ]
      end

      def minute_bucket(value)
        value.to_time.utc.change(sec: 0, usec: 0)
      end

      def next_minute(value)
        minute_bucket(value) + FLUSH_INTERVAL
      end
    end
  end
end
