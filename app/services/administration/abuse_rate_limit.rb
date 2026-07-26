# frozen_string_literal: true

require "digest"

module Administration
  # Applies public-entry throttles on independent account and IP dimensions.
  # Limits and windows can be overridden with SiteSetting keys shaped as:
  #   security.rate_limits.<action>.<dimension>_{limit,window_seconds}
  class AbuseRateLimit < ApplicationService
    POLICIES = {
      login: {
        account: { limit: 10, window_seconds: 15.minutes.to_i },
        ip: { limit: 30, window_seconds: 15.minutes.to_i }
      },
      registration: {
        account: { limit: 3, window_seconds: 24.hours.to_i },
        ip: { limit: 5, window_seconds: 1.hour.to_i }
      },
      search: {
        account: { limit: 30, window_seconds: 1.minute.to_i },
        ip: { limit: 60, window_seconds: 1.minute.to_i }
      },
      search_suggest: {
        account: { limit: 60, window_seconds: 1.minute.to_i },
        ip: { limit: 120, window_seconds: 1.minute.to_i }
      },
      preview: {
        account: { limit: 30, window_seconds: 1.minute.to_i },
        ip: { limit: 60, window_seconds: 1.minute.to_i }
      },
      upload: {
        account: { limit: 30, window_seconds: 1.hour.to_i },
        ip: { limit: 90, window_seconds: 1.hour.to_i }
      },
      topic: {
        account: { limit: 5, window_seconds: 1.hour.to_i },
        ip: { limit: 20, window_seconds: 1.hour.to_i }
      },
      reply: {
        account: { limit: 20, window_seconds: 1.hour.to_i },
        ip: { limit: 60, window_seconds: 1.hour.to_i }
      },
      reaction: {
        account: {
          limit: 0,
          window_seconds: 1.minute.to_i,
          limit_key: "forum.max_reactions_per_minute"
        },
        ip: { limit: 180, window_seconds: 1.minute.to_i }
      },
      report: {
        account: {
          limit: 10,
          window_seconds: 1.hour.to_i,
          limit_key: "forum.max_reports_per_hour"
        },
        ip: { limit: 30, window_seconds: 1.hour.to_i }
      },
      private_message: {
        account: { limit: 10, window_seconds: 1.minute.to_i },
        ip: { limit: 30, window_seconds: 1.minute.to_i }
      }
    }.freeze

    MAX_LIMIT = 100_000
    MAX_WINDOW_SECONDS = 30.days.to_i

    class << self
      def policy_rows
        POLICIES.flat_map do |action, dimensions|
          dimensions.map do |dimension, defaults|
            {
              action: action,
              dimension: dimension,
              limit: effective_value(action, dimension, :limit),
              window_seconds: effective_value(action, dimension, :window_seconds)
            }
          end
        end
      end

      def setting_key(action, dimension, attribute)
        validate_policy_coordinates!(action, dimension, attribute)
        "security.rate_limits.#{action}.#{dimension}_#{attribute}"
      end

      def effective_value(action, dimension, attribute)
        defaults = policy_defaults(action, dimension)
        default = defaults.fetch(attribute)
        legacy_key = defaults[:"#{attribute}_key"]
        fallback =
          if legacy_key
            configured_integer(
              legacy_key,
              default: default,
              min: minimum_for(attribute),
              max: maximum_for(attribute)
            )
          else
            default
          end

        configured_integer(
          setting_key(action, dimension, attribute),
          default: fallback,
          min: minimum_for(attribute),
          max: maximum_for(attribute)
        )
      end

      def policy_defaults(action, dimension)
        POLICIES.fetch(action.to_sym).fetch(dimension.to_sym)
      rescue KeyError
        raise ArgumentError, "Unknown abuse rate-limit policy coordinate: #{action}.#{dimension}"
      end

      def minimum_for(attribute)
        attribute.to_sym == :limit ? 0 : 1
      end

      def maximum_for(attribute)
        attribute.to_sym == :limit ? MAX_LIMIT : MAX_WINDOW_SECONDS
      end

      private

      def validate_policy_coordinates!(action, dimension, attribute)
        policy_defaults(action, dimension)
        return if %i[limit window_seconds].include?(attribute.to_sym)

        raise ArgumentError, "Unknown abuse rate-limit attribute: #{attribute}"
      end

      def configured_integer(key, default:, min:, max:)
        parsed = Integer(SiteSetting.get(key, default.to_s), exception: false)
        return default unless parsed&.between?(min, max)

        parsed
      end
    end

    def initialize(action:, account: nil, ip_address: nil)
      @action = action.to_sym
      @account = account
      @ip_address = ip_address.to_s.strip.presence
    end

    def call
      policy = POLICIES.fetch(@action) do
        raise ArgumentError, "Unknown abuse rate-limit policy: #{@action}"
      end

      dimensions(policy).each do |dimension, identifier, _defaults|
        limit = self.class.effective_value(@action, dimension, :limit)
        next if limit.zero?

        window_seconds = self.class.effective_value(@action, dimension, :window_seconds)

        result = Administration::RateLimiter.call(
          key: counter_key(dimension, identifier),
          limit: limit,
          window: window_seconds.seconds
        )
        return result if result.failure?
      end

      ServiceResult.success
    end

    private

    def dimensions(policy)
      values = []
      account_identifier = normalized_account
      values << [ :account, account_identifier, policy.fetch(:account) ] if account_identifier
      values << [ :ip, @ip_address, policy.fetch(:ip) ] if @ip_address
      values
    end

    def normalized_account
      value = @account.respond_to?(:id) ? @account.id : @account
      value.to_s.strip.downcase.presence
    end

    def counter_key(dimension, identifier)
      digest = Digest::SHA256.hexdigest(identifier)
      "abuse:#{@action}:#{dimension}:#{digest}"
    end
  end
end
