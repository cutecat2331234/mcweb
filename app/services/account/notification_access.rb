# frozen_string_literal: true

require "thread"

module Account
  # Dispatches notification visibility checks to the owning product domain.
  # Unknown domains retain only the account-ownership/session check, while
  # forum notifications continue to use the full Community privacy guard.
  class NotificationAccess
    PREFIX_FORMAT = /\A[a-z0-9][a-z0-9_.:-]*\z/
    BUILTIN_POLICIES = {
      "forum." => Community::NotificationAccess
    }.freeze

    @registry = BUILTIN_POLICIES.dup.freeze
    @registry_mutex = Mutex.new

    class << self
      def register(prefixes:, policy:)
        values = Array(prefixes).map(&:to_s).uniq
        raise ArgumentError, "notification access prefixes are required" if values.empty?
        raise ArgumentError, "invalid notification access prefix" unless values.all? { |prefix| prefix.match?(PREFIX_FORMAT) }
        raise ArgumentError, "notification access policy must be constructible" unless policy.respond_to?(:new)

        @registry_mutex.synchronize do
          protected_prefix = values.find do |prefix|
            BUILTIN_POLICIES.key?(prefix) && BUILTIN_POLICIES.fetch(prefix) != policy
          end
          if protected_prefix
            raise ArgumentError,
              "notification access policy for #{protected_prefix} is built in"
          end

          retained_registry = registry.except(*values)
          conflicting_prefix = retained_registry.find do |registered_prefix, registered_policy|
            registered_policy != policy && values.any? do |prefix|
              prefix.start_with?(registered_prefix) || registered_prefix.start_with?(prefix)
            end
          end&.first
          if conflicting_prefix
            raise ArgumentError,
              "notification access prefixes overlap with #{conflicting_prefix}"
          end

          additions = values.to_h { |prefix| [ prefix, policy ] }
          @registry = retained_registry.merge(additions).freeze
        end
        policy
      end

      def visible?(notification:, user:)
        new(user:, notifications: [ notification ]).visible?(notification)
      end

      private

      def registry
        @registry
      end

      def policy_for(notification_type)
        value = notification_type.to_s
        registry
          .sort_by { |prefix, _policy| -prefix.length }
          .find { |prefix, _policy| value.start_with?(prefix) }
          &.last
      end
    end

    def initialize(user:, notifications:)
      @user = user
      @notifications = Array(notifications)
      @policy_instances = build_policy_instances
    end

    def visible?(notification)
      return false unless @user&.session_eligible?
      return false unless notification.user_id == @user.id

      policy = self.class.send(:policy_for, notification.notification_type)
      return true unless policy

      policy_instance(policy, notification).visible?(notification)
    end

    private

    def build_policy_instances
      return {} unless @user&.session_eligible?

      @notifications
        .select { |notification| notification.user_id == @user.id }
        .group_by { |notification| self.class.send(:policy_for, notification.notification_type) }
        .reject { |policy, _notifications| policy.nil? }
        .to_h do |policy, notifications|
          [ policy, policy.new(user: @user, notifications:) ]
        end
    end

    def policy_instance(policy, notification)
      @policy_instances[policy] ||= policy.new(user: @user, notifications: [ notification ])
    end
  end
end
