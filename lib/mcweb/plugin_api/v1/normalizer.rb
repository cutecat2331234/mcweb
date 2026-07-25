# frozen_string_literal: true

require "date"
require "time"

module Mcweb
  module PluginApi
    module V1
      module Normalizer
        MAX_DEPTH = 64

        module_function

        def call(value)
          normalize(value, {}, 0)
        end

        def normalize(value, seen, depth)
          case value
          when nil, true, false, Numeric
            value
          when String
            value.dup.freeze
          when Symbol
            value.to_s.freeze
          when Time, Date, DateTime
            value.iso8601.freeze
          when Hash
            depth >= MAX_DEPTH ? maximum_depth : normalize_hash(value, seen, depth + 1)
          when Array
            depth >= MAX_DEPTH ? maximum_depth : normalize_array(value, seen, depth + 1)
          else
            active_record?(value) ? normalize_record(value) : { "type" => value.class.name.to_s.dup.freeze }.freeze
          end
        end
        private_class_method :normalize

        def normalize_hash(value, seen, depth)
          return circular_reference if seen[value.object_id]

          begin
            seen[value.object_id] = true
            value.each_with_object({}) do |(key, item), result|
              result[key.to_s.dup.freeze] = normalize(item, seen, depth)
            end.freeze
          ensure
            seen.delete(value.object_id)
          end
        end
        private_class_method :normalize_hash

        def normalize_array(value, seen, depth)
          return circular_reference if seen[value.object_id]

          begin
            seen[value.object_id] = true
            value.map { |item| normalize(item, seen, depth) }.freeze
          ensure
            seen.delete(value.object_id)
          end
        end
        private_class_method :normalize_array

        def normalize_record(record)
          snapshot = {
            "type" => record.class.name.to_s.dup.freeze,
            "id" => normalize(record.id, {}, 0)
          }
          if record.respond_to?(:public_id) && record.public_id.present?
            snapshot["public_id"] = record.public_id.to_s.dup.freeze
          end
          snapshot.freeze
        end
        private_class_method :normalize_record

        def active_record?(value)
          defined?(ActiveRecord::Base) && value.is_a?(ActiveRecord::Base)
        end
        private_class_method :active_record?

        def circular_reference
          { "type" => "circular_reference".freeze }.freeze
        end
        private_class_method :circular_reference

        def maximum_depth
          { "type" => "maximum_depth".freeze }.freeze
        end
        private_class_method :maximum_depth
      end
    end
  end
end
