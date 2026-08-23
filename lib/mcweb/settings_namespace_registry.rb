# frozen_string_literal: true

require "json"
require "time"
require "uri"

module Mcweb
  module SettingsNamespaceRegistry
    SURFACES = %i[basic generic dedicated internal].freeze
    TYPES = %i[boolean email enum integer json locale string timestamp url].freeze
    SENSITIVITIES = %i[public confidential secret].freeze

    Registration = Struct.new(
      :prefix,
      :owner,
      :surface,
      :sensitivity,
      keyword_init: true
    )
    SettingRegistration = Struct.new(
      :key,
      :owner,
      :surface,
      :type,
      :sensitivity,
      :writable,
      :constraints,
      keyword_init: true
    )

    class ValidationError < StandardError
      attr_reader :key, :code, :details

      def initialize(key:, code:, details: {})
        @key = key.to_s
        @code = code.to_s
        @details = details.transform_keys(&:to_sym).freeze
        super("site_setting_#{@code}")
      end
    end

    class Registry
      PREFIX_PATTERN = /\A[a-z][a-z0-9_-]*(?:\.[a-z0-9_-]+)*\.\z/
      KEY_PATTERN = /\A[a-z][a-z0-9_-]*(?:\.[a-z0-9_-]+)+\z/
      OWNER_PATTERN = /\A[a-z][a-z0-9_.-]*\z/
      SENSITIVE_KEY_PATTERN = /(?:^|[._-])(secret|password|token|private_key)(?:$|[._-])/i

      def initialize
        @mutex = Mutex.new
        @registrations = {}.freeze
        @settings = {}.freeze
      end

      def register(prefix:, owner:, surface: :dedicated, sensitivity: :public)
        normalized_prefix = normalize_prefix(prefix)
        normalized_owner = normalize_owner(owner)
        normalized_surface = normalize_surface(surface)
        normalized_sensitivity = normalize_sensitivity(sensitivity)

        @mutex.synchronize do
          existing = @registrations[normalized_prefix]
          if existing
            return existing if existing.owner == normalized_owner &&
              existing.surface == normalized_surface &&
              existing.sensitivity == normalized_sensitivity

            raise ArgumentError, "settings_namespace_owner_conflict"
          end

          registration = Registration.new(
            prefix: normalized_prefix,
            owner: normalized_owner,
            surface: normalized_surface,
            sensitivity: normalized_sensitivity
          ).freeze
          @registrations = @registrations.merge(normalized_prefix => registration).freeze
          registration
        end
      end

      def register_setting(
        key:,
        owner: nil,
        surface: nil,
        type: :string,
        sensitivity: nil,
        writable: true,
        constraints: {}
      )
        normalized_key = normalize_key(key)
        namespace = registration_for(normalized_key)
        normalized_owner = normalize_owner(owner || namespace&.owner)
        normalized_surface = normalize_surface(surface || namespace&.surface)
        normalized_type = normalize_type(type)
        normalized_sensitivity = normalize_sensitivity(
          sensitivity || namespace&.sensitivity || :public
        )
        normalized_constraints = normalize_constraints(constraints)

        @mutex.synchronize do
          existing = @settings[normalized_key]
          candidate = SettingRegistration.new(
            key: normalized_key,
            owner: normalized_owner,
            surface: normalized_surface,
            type: normalized_type,
            sensitivity: normalized_sensitivity,
            writable: !!writable,
            constraints: normalized_constraints
          ).freeze
          if existing
            return existing if existing == candidate

            raise ArgumentError, "site_setting_registration_conflict"
          end

          @settings = @settings.merge(normalized_key => candidate).freeze
          candidate
        end
      end

      def registration_for(key)
        candidate = key.to_s
        return if candidate.empty?

        registrations
          .select { |registration| candidate.start_with?(registration.prefix) }
          .max_by { |registration| registration.prefix.length }
      end

      def setting_for(key)
        @settings[key.to_s]
      end

      def owner_for(key)
        setting_for(key)&.owner || registration_for(key)&.owner
      end

      def protected?(key)
        !registration_for(key).nil?
      end

      def visible_on?(key, surface:)
        normalized_surface = normalize_surface(surface)
        setting = setting_for(key)
        return setting.surface == normalized_surface if setting
        return false if protected?(key)

        normalized_surface == :generic
      end

      def writable_on?(key, surface:)
        setting = setting_for(key)
        return setting.writable && visible_on?(key, surface:) if setting
        return false if protected?(key)

        normalize_surface(surface) == :generic
      end

      def sensitive?(key)
        setting = setting_for(key)
        return setting.sensitivity != :public if setting

        namespace = registration_for(key)
        return true if namespace && namespace.sensitivity != :public

        key.to_s.match?(SENSITIVE_KEY_PATTERN)
      end

      def input_type_for(key)
        return :password if sensitive?(key)

        case setting_for(key)&.type
        when :boolean then :boolean
        when :integer then :number
        else :text
        end
      end

      def normalize_for_write(key, value, surface:, owner: nil)
        normalized_key = key.to_s
        normalized_surface = normalize_surface(surface)
        setting = setting_for(normalized_key)

        unless writable_on?(normalized_key, surface: normalized_surface)
          code = setting&.writable == false ? :read_only : :wrong_surface
          raise ValidationError.new(key: normalized_key, code:)
        end
        if owner && setting && setting.owner != normalize_owner(owner)
          raise ValidationError.new(key: normalized_key, code: :wrong_owner)
        end

        return value.to_s unless setting

        normalize_value(setting, value)
      end

      def registrations
        @registrations.values.sort_by(&:prefix).freeze
      end

      def settings
        @settings.values.sort_by(&:key).freeze
      end

      private

      def normalize_prefix(prefix)
        value = prefix.to_s.strip
        raise ArgumentError, "settings_namespace_prefix_invalid" unless value.match?(PREFIX_PATTERN)

        value
      end

      def normalize_key(key)
        value = key.to_s.strip
        raise ArgumentError, "site_setting_key_invalid" unless value.match?(KEY_PATTERN)

        value
      end

      def normalize_owner(owner)
        value = owner.to_s.strip
        raise ArgumentError, "settings_namespace_owner_invalid" unless value.match?(OWNER_PATTERN)

        value
      end

      def normalize_surface(surface)
        value = surface.to_sym
        raise ArgumentError, "site_setting_surface_invalid" unless SURFACES.include?(value)

        value
      end

      def normalize_type(type)
        value = type.to_sym
        raise ArgumentError, "site_setting_type_invalid" unless TYPES.include?(value)

        value
      end

      def normalize_sensitivity(sensitivity)
        value = sensitivity.to_sym
        unless SENSITIVITIES.include?(value)
          raise ArgumentError, "site_setting_sensitivity_invalid"
        end

        value
      end

      def normalize_constraints(constraints)
        constraints.to_h.transform_keys(&:to_sym).transform_values do |value|
          value.is_a?(Array) ? value.map(&:to_s).freeze : value
        end.freeze
      end

      def normalize_value(setting, raw_value)
        constraints = setting.constraints
        value = raw_value.to_s
        value = value.strip if constraints[:strip]

        if constraints[:required] && value.empty?
          raise ValidationError.new(key: setting.key, code: :required)
        end
        if constraints[:max_length] && value.length > constraints[:max_length]
          raise ValidationError.new(
            key: setting.key,
            code: :too_long,
            details: { max: constraints[:max_length] }
          )
        end
        if constraints[:reject_control_characters] && value.match?(/[[:cntrl:]]/)
          raise ValidationError.new(key: setting.key, code: :invalid_characters)
        end

        case setting.type
        when :boolean
          normalize_boolean(setting, value)
        when :integer
          normalize_integer(setting, value)
        when :url
          normalize_url(setting, value)
        when :email
          normalize_email(setting, value)
        when :locale
          normalize_allowed_value(setting, value, :invalid_locale)
        when :enum
          normalize_allowed_value(setting, value, :invalid_choice)
        when :json
          normalize_json(setting, value)
        when :timestamp
          normalize_timestamp(setting, value)
        else
          value
        end
      end

      def normalize_boolean(setting, value)
        truthy = %w[true 1].include?(value.downcase)
        falsey = %w[false 0].include?(value.downcase)
        unless truthy || falsey
          raise ValidationError.new(key: setting.key, code: :invalid_boolean)
        end

        if truthy
          setting.constraints.fetch(:true_value, "true").to_s
        else
          setting.constraints.fetch(:false_value, "false").to_s
        end
      end

      def normalize_integer(setting, value)
        parsed = Integer(value, 10, exception: false)
        raise ValidationError.new(key: setting.key, code: :invalid_integer) unless parsed

        minimum = setting.constraints[:min]
        maximum = setting.constraints[:max]
        if !minimum.nil? && parsed < minimum
          raise ValidationError.new(
            key: setting.key,
            code: :below_minimum,
            details: { min: minimum }
          )
        end
        if !maximum.nil? && parsed > maximum
          raise ValidationError.new(
            key: setting.key,
            code: :above_maximum,
            details: { max: maximum }
          )
        end

        parsed.to_s
      end

      def normalize_url(setting, value)
        return "" if value.empty? && setting.constraints.fetch(:allow_blank, true)

        uri = URI.parse(value)
        valid = uri.is_a?(URI::HTTP) && uri.host && uri.userinfo.nil?
        if setting.constraints[:origin_only]
          valid &&= (uri.path.nil? || uri.path.empty? || uri.path == "/")
          valid &&= uri.query.nil? && uri.fragment.nil?
        end
        raise ValidationError.new(key: setting.key, code: :invalid_url) unless valid

        value.sub(%r{/+\z}, "")
      rescue URI::InvalidURIError
        raise ValidationError.new(key: setting.key, code: :invalid_url)
      end

      def normalize_email(setting, value)
        return "" if value.empty? && setting.constraints.fetch(:allow_blank, true)

        unless value.match?(URI::MailTo::EMAIL_REGEXP)
          raise ValidationError.new(key: setting.key, code: :invalid_email)
        end

        value
      end

      def normalize_allowed_value(setting, value, code)
        allowed = Array(setting.constraints[:in]).map(&:to_s)
        unless allowed.include?(value)
          raise ValidationError.new(key: setting.key, code:)
        end

        value
      end

      def normalize_json(setting, value)
        parsed = JSON.parse(value)
        expected = setting.constraints[:kind]&.to_sym
        valid = expected.nil? ||
          (expected == :array && parsed.is_a?(Array)) ||
          (expected == :object && parsed.is_a?(Hash))
        raise ValidationError.new(key: setting.key, code: :invalid_json) unless valid

        JSON.generate(parsed)
      rescue JSON::ParserError
        raise ValidationError.new(key: setting.key, code: :invalid_json)
      end

      def normalize_timestamp(setting, value)
        Time.iso8601(value).iso8601
      rescue ArgumentError
        raise ValidationError.new(key: setting.key, code: :invalid_timestamp)
      end
    end

    DEFAULT = Registry.new

    module_function

    def register(**attributes)
      DEFAULT.register(**attributes)
    end

    def register_setting(**attributes)
      DEFAULT.register_setting(**attributes)
    end

    def registration_for(key)
      DEFAULT.registration_for(key)
    end

    def setting_for(key)
      DEFAULT.setting_for(key)
    end

    def owner_for(key)
      DEFAULT.owner_for(key)
    end

    def protected?(key)
      DEFAULT.protected?(key)
    end

    def visible_on?(key, surface:)
      DEFAULT.visible_on?(key, surface:)
    end

    def writable_on?(key, surface:)
      DEFAULT.writable_on?(key, surface:)
    end

    def sensitive?(key)
      DEFAULT.sensitive?(key)
    end

    def input_type_for(key)
      DEFAULT.input_type_for(key)
    end

    def normalize_for_write(key, value, surface:, owner: nil)
      DEFAULT.normalize_for_write(key, value, surface:, owner:)
    end

    def registrations
      DEFAULT.registrations
    end

    def settings
      DEFAULT.settings
    end
  end
end
