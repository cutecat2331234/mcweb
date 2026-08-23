# frozen_string_literal: true

module Website
  class ThemeRevisionDiff < ApplicationService
    MISSING = Object.new.freeze

    def initialize(before_snapshot:, after_snapshot:)
      @before = ThemeSnapshot.call(snapshot: before_snapshot)
      @after = ThemeSnapshot.call(snapshot: after_snapshot)
    end

    def call
      before_values = flatten(@before)
      after_values = flatten(@after)

      (before_values.keys | after_values.keys).sort.filter_map do |path|
        before_value = before_values.fetch(path, MISSING)
        after_value = after_values.fetch(path, MISSING)
        next if before_value != MISSING && after_value != MISSING && before_value == after_value

        {
          path: path,
          before: before_value == MISSING ? nil : before_value,
          after: after_value == MISSING ? nil : after_value,
          before_present: before_value != MISSING,
          after_present: after_value != MISSING
        }
      end
    end

    private

    def flatten(value, prefix = nil, result = {})
      if value.is_a?(Hash)
        value.each do |key, nested|
          path = [ prefix, key ].compact.join(".")
          flatten(nested, path, result)
        end
      else
        result[prefix] = value
      end
      result
    end
  end
end
