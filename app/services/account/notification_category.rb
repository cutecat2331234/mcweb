# frozen_string_literal: true

require "thread"

module Account
  # Classifies account notifications by a registered notification-type prefix.
  # Unknown types deliberately fall back to the system category so downstream
  # editions and plugins remain visible without being mislabeled as forum data.
  class NotificationCategory
    DEFAULT_CATEGORY = "system"
    CATEGORY_FORMAT = /\A[a-z][a-z0-9_]*\z/
    PREFIX_FORMAT = /\A[a-z0-9][a-z0-9_.:-]*\z/
    BUILTIN_PREFIXES = {
      "forum" => [ "forum." ],
      "commerce" => [ "commerce." ]
    }.freeze

    @registry = BUILTIN_PREFIXES.transform_values(&:dup).transform_values(&:freeze).freeze
    @registry_mutex = Mutex.new

    class << self
      def register(category, prefixes:)
        key = category.to_s
        values = Array(prefixes).map(&:to_s).uniq
        raise ArgumentError, "invalid notification category" unless key.match?(CATEGORY_FORMAT)
        raise ArgumentError, "system is the fallback notification category" if key == DEFAULT_CATEGORY
        raise ArgumentError, "notification category prefixes are required" if values.empty?
        raise ArgumentError, "invalid notification category prefix" unless values.all? { |prefix| prefix.match?(PREFIX_FORMAT) }

        @registry_mutex.synchronize do
          conflicting_category = registry.find do |registered_category, registered_prefixes|
            registered_category != key && registered_prefixes.any? do |registered_prefix|
              values.any? do |prefix|
                prefix.start_with?(registered_prefix) || registered_prefix.start_with?(prefix)
              end
            end
          end&.first
          if conflicting_category
            raise ArgumentError,
              "notification category prefixes overlap with #{conflicting_category}"
          end

          combined = (registry.fetch(key, []) + values).uniq.freeze
          @registry = registry.merge(key => combined).freeze
        end
        key
      end

      def categories
        [ *registry.keys, DEFAULT_CATEGORY ]
      end

      def normalize(value)
        key = value.to_s
        return nil if key.blank? || key == "all"

        key if categories.include?(key)
      end

      def for(notification_type)
        value = notification_type.to_s
        matching_prefixes.find { |_category, prefix| value.start_with?(prefix) }&.first || DEFAULT_CATEGORY
      end

      def apply(scope, category)
        key = normalize(category)
        return scope unless key

        if key == DEFAULT_CATEGORY
          patterns = matching_prefixes.map { |_registered_category, prefix| "#{sanitize_prefix(prefix)}%" }
          return scope if patterns.empty?

          column = scope.klass.arel_table[:notification_type]
          predicate = patterns
            .map { |pattern| column.does_not_match(pattern, "\\", true) }
            .reduce(&:and)
          return scope.where(predicate)
        end

        prefixes = registry.fetch(key)
        patterns = prefixes.map { |prefix| "#{sanitize_prefix(prefix)}%" }
        column = scope.klass.arel_table[:notification_type]
        predicate = patterns
          .map { |pattern| column.matches(pattern, "\\", true) }
          .reduce(&:or)
        scope.where(predicate)
      end

      def label(category)
        key = normalize(category) || DEFAULT_CATEGORY
        I18n.t("mcweb.account.notifications.categories.#{key}", default: key.humanize)
      end

      private

      def registry
        @registry
      end

      def matching_prefixes
        registry.flat_map do |category, prefixes|
          prefixes.map { |prefix| [ category, prefix ] }
        end.sort_by { |_category, prefix| -prefix.length }
      end

      def sanitize_prefix(prefix)
        ActiveRecord::Base.sanitize_sql_like(prefix)
      end
    end
  end
end
