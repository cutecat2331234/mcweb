# frozen_string_literal: true

module Minecraft
  # A bounded extension point for product layers that need to prevent an
  # otherwise valid identity unlink. A checker returns nil to allow the
  # operation or a stable snake-case error code to deny it. Exceptions and
  # malformed results fail closed.
  #
  #   Minecraft::IdentityUnlinkRestrictions.register(
  #     key: "edition.active_workflow"
  #   ) do |user:, identity_link:|
  #     Edition::ActiveWorkflow.exists?(user: user, identity_link: identity_link) ?
  #       :edition_identity_unlink_active_workflow : nil
  #   end
  class IdentityUnlinkRestrictions
    MAX_REGISTRATIONS = 16
    KEY_PATTERN = /\A[a-z][a-z0-9_.]{0,79}\z/
    ERROR_CODE_PATTERN = /\A[a-z][a-z0-9_]{0,99}\z/

    class << self
      def register(key:, callable: nil, &block)
        default_registry.register(key: key, callable: callable, &block)
      end

      def check(user:, identity_link:)
        default_registry.check(user: user, identity_link: identity_link)
      end

      def registered_keys
        default_registry.registered_keys
      end

      private

      def default_registry
        @default_registry ||= new
      end
    end

    def initialize(max_registrations: MAX_REGISTRATIONS, logger: Rails.logger)
      unless max_registrations.to_i.between?(1, MAX_REGISTRATIONS)
        raise ArgumentError, "max_registrations must be between 1 and #{MAX_REGISTRATIONS}"
      end

      @max_registrations = max_registrations.to_i
      @logger = logger
      @mutex = Mutex.new
      @entries = {}.freeze
    end

    def register(key:, callable: nil, &block)
      normalized_key = key.to_s.strip
      checker = callable || block
      raise ArgumentError, "invalid identity unlink restriction key" unless KEY_PATTERN.match?(normalized_key)
      raise ArgumentError, "identity unlink restriction must respond to call" unless checker.respond_to?(:call)

      @mutex.synchronize do
        raise ArgumentError, "identity unlink restriction already registered: #{normalized_key}" if @entries.key?(normalized_key)
        raise ArgumentError, "identity unlink restriction registration limit reached" if @entries.length >= @max_registrations

        @entries = @entries.merge(normalized_key => checker).freeze
      end

      self
    end

    def check(user:, identity_link:)
      entries_snapshot.each do |key, checker|
        decision = checker.call(user: user, identity_link: identity_link)
        result = normalize_decision(decision)
        return result if result&.failure?
      rescue StandardError => error
        log_failure(key, error)
        return unavailable
      end

      ServiceResult.success
    end

    def registered_keys
      entries_snapshot.keys.freeze
    end

    private

    def entries_snapshot
      @mutex.synchronize { @entries }
    end

    def normalize_decision(decision)
      return if decision.nil?
      return if decision.is_a?(ServiceResult) && decision.success?

      if decision.is_a?(ServiceResult) && decision.failure?
        code = decision.code.to_s
        return decision if ERROR_CODE_PATTERN.match?(code)

        raise ArgumentError, "identity unlink restriction returned a failure without a stable code"
      end

      code = decision.to_s
      return failure(code) if decision.is_a?(Symbol) && ERROR_CODE_PATTERN.match?(code)

      raise ArgumentError, "identity unlink restriction returned an unsupported decision"
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end

    def unavailable
      failure(:minecraft_identity_unlink_restriction_unavailable)
    end

    def log_failure(key, error)
      @logger&.error(
        "[Minecraft::IdentityUnlinkRestrictions] checker=#{key} failed with #{error.class}"
      )
    end
  end
end
