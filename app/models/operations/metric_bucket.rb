# frozen_string_literal: true

module Operations
  class MetricBucket < ApplicationRecord
    self.table_name = "operations_metric_buckets"

    validates :bucket_at, :metric_name, :dimensions_key, presence: true
    validates :metric_name,
      inclusion: { in: ->(_record) { Metrics::Catalog.metric_names } }
    validates :dimensions_key,
      length: { is: 64 },
      format: { with: /\A[0-9a-f]{64}\z/ }
    validates :sample_count,
      numericality: { only_integer: true, greater_than: 0 }
    validates :value_sum, :value_min, :value_max,
      numericality: { greater_than_or_equal_to: 0 }
    validate :valid_value_range

    scope :within, ->(from:, to:) {
      where(bucket_at: from...to)
    }

    class << self
      def atomic_merge!(entries)
        rows = Array(entries).map { |entry| persistence_row(entry) }
        return 0 if rows.empty?

        Operations::Metrics.silence do
          upsert_all(
            rows,
            unique_by: :idx_operations_metric_buckets_identity,
            on_duplicate: Arel.sql(<<~SQL.squish)
              sample_count =
                operations_metric_buckets.sample_count + EXCLUDED.sample_count,
              value_sum =
                operations_metric_buckets.value_sum + EXCLUDED.value_sum,
              value_min =
                LEAST(operations_metric_buckets.value_min, EXCLUDED.value_min),
              value_max =
                GREATEST(operations_metric_buckets.value_max, EXCLUDED.value_max),
              updated_at = EXCLUDED.updated_at
            SQL
          )
        end
        rows.length
      end

      private

      def persistence_row(entry)
        now = Time.current
        {
          bucket_at: entry.fetch(:bucket_at).to_time.utc.change(sec: 0, usec: 0),
          metric_name: entry.fetch(:metric_name),
          dimensions_key: entry.fetch(:dimensions_key),
          dimensions: entry.fetch(:dimensions),
          sample_count: entry.fetch(:sample_count),
          value_sum: entry.fetch(:value_sum),
          value_min: entry.fetch(:value_min),
          value_max: entry.fetch(:value_max),
          created_at: now,
          updated_at: now
        }
      end
    end

    private

    def valid_value_range
      return if value_min.nil? || value_max.nil?
      return if value_min <= value_max

      errors.add(:value_min, :less_than_or_equal_to, count: value_max)
    end
  end
end
