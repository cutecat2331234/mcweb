# frozen_string_literal: true

module Mcweb
  module SettingsNamespaceRegistry
    Registration = Struct.new(:prefix, :owner, keyword_init: true)

    class Registry
      PREFIX_PATTERN = /\A[a-z][a-z0-9_-]*(?:\.[a-z0-9_-]+)*\.\z/
      OWNER_PATTERN = /\A[a-z][a-z0-9_.-]*\z/

      def initialize
        @mutex = Mutex.new
        @registrations = {}.freeze
      end

      def register(prefix:, owner:)
        normalized_prefix = normalize_prefix(prefix)
        normalized_owner = normalize_owner(owner)

        @mutex.synchronize do
          existing = @registrations[normalized_prefix]
          if existing
            return existing if existing.owner == normalized_owner

            raise ArgumentError, "settings_namespace_owner_conflict"
          end

          registration = Registration.new(
            prefix: normalized_prefix,
            owner: normalized_owner
          ).freeze
          @registrations = @registrations.merge(normalized_prefix => registration).freeze
          registration
        end
      end

      def registration_for(key)
        candidate = key.to_s
        return if candidate.empty?

        registrations
          .select { |registration| candidate.start_with?(registration.prefix) }
          .max_by { |registration| registration.prefix.length }
      end

      def owner_for(key)
        registration_for(key)&.owner
      end

      def protected?(key)
        !registration_for(key).nil?
      end

      def registrations
        @registrations.values.sort_by(&:prefix).freeze
      end

      private

      def normalize_prefix(prefix)
        value = prefix.to_s.strip
        raise ArgumentError, "settings_namespace_prefix_invalid" unless value.match?(PREFIX_PATTERN)

        value
      end

      def normalize_owner(owner)
        value = owner.to_s.strip
        raise ArgumentError, "settings_namespace_owner_invalid" unless value.match?(OWNER_PATTERN)

        value
      end
    end

    DEFAULT = Registry.new

    module_function

    def register(prefix:, owner:)
      DEFAULT.register(prefix:, owner:)
    end

    def registration_for(key)
      DEFAULT.registration_for(key)
    end

    def owner_for(key)
      DEFAULT.owner_for(key)
    end

    def protected?(key)
      DEFAULT.protected?(key)
    end

    def registrations
      DEFAULT.registrations
    end
  end
end
