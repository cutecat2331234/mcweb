# frozen_string_literal: true

module Administration
  class UpdateAbuseRateLimitPolicies < ApplicationService
    ATTRIBUTES = %i[limit window_seconds].freeze

    def initialize(policies:)
      @policies = policies.to_h.deep_stringify_keys
    end

    def call
      values, errors = validate_values
      return ServiceResult.failure(error: validation_message, errors: errors) if errors.any?

      before_state = current_state
      changed_values = values.select do |path, value|
        before_state.fetch(path) != value
      end

      SiteSetting.transaction do
        changed_values.each do |path, value|
          action, dimension, attribute = path.split(".")
          SiteSetting.set(
            Administration::AbuseRateLimit.setting_key(action, dimension, attribute),
            value.to_s
          )
        end
      end

      ServiceResult.success(
        changed_paths: changed_values.keys,
        before_state: before_state.slice(*changed_values.keys),
        after_state: changed_values
      )
    end

    private

    def validate_values
      values = {}
      errors = {}

      Administration::AbuseRateLimit::POLICIES.each do |action, dimensions|
        dimensions.each_key do |dimension|
          ATTRIBUTES.each do |attribute|
            path = "#{action}.#{dimension}.#{attribute}"
            parsed = parse_integer(@policies.dig(action.to_s, dimension.to_s, attribute.to_s))
            range = valid_range(attribute)

            if parsed.nil? || !range.cover?(parsed)
              errors["policies.#{path}"] = [
                I18n.t(
                  "mcweb.admin.rate_limits.errors.#{attribute}",
                  min: range.begin,
                  max: range.end
                )
              ]
            else
              values[path] = parsed
            end
          end
        end
      end

      [ values, errors ]
    end

    def current_state
      Administration::AbuseRateLimit.policy_rows.each_with_object({}) do |policy, state|
        action = policy.fetch(:action)
        dimension = policy.fetch(:dimension)
        ATTRIBUTES.each do |attribute|
          state["#{action}.#{dimension}.#{attribute}"] = policy.fetch(attribute)
        end
      end
    end

    def parse_integer(value)
      Integer(value.to_s, 10, exception: false)
    end

    def valid_range(attribute)
      Administration::AbuseRateLimit.minimum_for(attribute)..
        Administration::AbuseRateLimit.maximum_for(attribute)
    end

    def validation_message
      I18n.t("mcweb.admin.rate_limits.errors.invalid")
    end
  end
end
