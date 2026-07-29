# frozen_string_literal: true

class CreateOperationsMetricBuckets < ActiveRecord::Migration[8.1]
  def change
    create_table :operations_metric_buckets do |t|
      t.datetime :bucket_at, null: false
      t.string :metric_name, null: false, limit: 96
      t.string :dimensions_key, null: false, limit: 64
      t.jsonb :dimensions, null: false, default: {}
      t.bigint :sample_count, null: false, default: 0
      t.decimal :value_sum, null: false, default: 0,
        precision: 30, scale: 6
      t.decimal :value_min, null: false, default: 0,
        precision: 20, scale: 6
      t.decimal :value_max, null: false, default: 0,
        precision: 20, scale: 6
      t.timestamps
    end

    add_index :operations_metric_buckets,
      [ :bucket_at, :metric_name, :dimensions_key ],
      unique: true,
      name: "idx_operations_metric_buckets_identity"
    add_index :operations_metric_buckets,
      [ :metric_name, :bucket_at ],
      name: "idx_operations_metric_buckets_trends"

    add_check_constraint :operations_metric_buckets,
      "sample_count > 0",
      name: "operations_metric_buckets_positive_samples"
    add_check_constraint :operations_metric_buckets,
      "value_min <= value_max",
      name: "operations_metric_buckets_value_range"
    add_check_constraint :operations_metric_buckets,
      "jsonb_typeof(dimensions) = 'object'",
      name: "operations_metric_buckets_dimensions_object"
  end
end
