# frozen_string_literal: true

require "ipaddr"
require "mail"
require "uri"

module Mcweb
  module ProductionEnvironment
    class InvalidConfiguration < StandardError; end

    Settings = Struct.new(
      :public_url,
      :allowed_hosts,
      :trusted_proxies,
      :smtp_settings,
      :mail_from,
      :storage_service,
      keyword_init: true
    ) do
      def default_url_options
        {
          protocol: "https",
          host: public_url.host,
          port: public_url.port == 443 ? nil : public_url.port
        }.compact.freeze
      end
    end

    TRUTHY_VALUES = %w[1 true yes on].freeze
    FALSY_VALUES = %w[0 false no off].freeze
    SMTP_AUTHENTICATIONS = %w[plain login cram_md5 none].freeze
    SMTP_TLS_MODES = %w[starttls tls].freeze
    UNIVERSAL_PROXY_RANGES = [
      IPAddr.new("0.0.0.0/0"),
      IPAddr.new("::/0")
    ].freeze

    class << self
      def load!(environment = ENV)
        load_selected!(environment)
      end

      # Developer Mode still runs against the real application database and
      # encryption boundary. Keep those production checks available without
      # forcing unrelated HTTPS, SMTP, host, or object-storage configuration.
      def validate_foundation!(environment = ENV)
        validate_application_secrets!(environment)
        validate_database_environment!(environment)
        true
      end

      def load_selected!(
        environment = ENV,
        public_origin: true,
        host_authorization: true,
        trusted_proxy_policy: true,
        mail: true,
        storage: true
      )
        validate_foundation!(environment)
        validate_action_mailbox_secret!(environment) if mail

        needs_public_url = public_origin || host_authorization || mail
        public_url = if needs_public_url
          parse_public_url!(required!(environment, "MCWEB_PUBLIC_URL"))
        end

        Settings.new(
          public_url: public_url,
          allowed_hosts: host_authorization ? allowed_hosts(environment, public_url.host) : nil,
          trusted_proxies: trusted_proxy_policy ? trusted_proxies(environment) : nil,
          smtp_settings: mail ? smtp_settings(environment, public_url.host) : nil,
          mail_from: mail ? mail_from(environment) : nil,
          storage_service: storage ? storage_service(environment) : nil
        ).freeze
      end

      private

      def validate_application_secrets!(environment)
        secret_key_base = required!(environment, "SECRET_KEY_BASE")
        reject_placeholder_value!(secret_key_base, "SECRET_KEY_BASE")
        if secret_key_base.bytesize < 64
          raise InvalidConfiguration, "SECRET_KEY_BASE must contain at least 64 bytes"
        end

        lockbox_master_key = required!(environment, "LOCKBOX_MASTER_KEY")
        reject_placeholder_value!(lockbox_master_key, "LOCKBOX_MASTER_KEY")
        unless lockbox_master_key.match?(/\A\h{64}\z/)
          raise InvalidConfiguration, "LOCKBOX_MASTER_KEY must contain exactly 64 hexadecimal characters"
        end
      end

      def validate_database_environment!(environment)
        database_url = environment["DATABASE_URL"].to_s.strip.presence
        if database_url
          url = URI.parse(database_url)
          unless %w[postgres postgresql].include?(url.scheme) && url.path.to_s.delete_prefix("/").present?
            raise InvalidConfiguration, "DATABASE_URL must be a PostgreSQL database URL"
          end
          reject_placeholder_value!(url.password, "DATABASE_URL password") if url.password
          return
        end

        host = environment["MCWEB_DATABASE_HOST"].to_s.strip.presence
        password = environment["MCWEB_DATABASE_PASSWORD"].to_s.presence
        reject_placeholder_value!(password, "MCWEB_DATABASE_PASSWORD") if password
        return unless host

        required!(environment, "MCWEB_DATABASE_USERNAME")
        required!(environment, "MCWEB_DATABASE_PASSWORD")
      rescue URI::InvalidURIError
        raise InvalidConfiguration, "DATABASE_URL must be a valid PostgreSQL database URL"
      end

      def validate_action_mailbox_secret!(environment)
        ingress = environment.fetch("MCWEB_ACTION_MAILBOX_INGRESS", "relay")
        return unless ingress == "relay"

        password = required!(environment, "RAILS_INBOUND_EMAIL_PASSWORD")
        reject_placeholder_value!(password, "RAILS_INBOUND_EMAIL_PASSWORD")
        if password.bytesize < 32
          raise InvalidConfiguration, "RAILS_INBOUND_EMAIL_PASSWORD must contain at least 32 bytes"
        end
      end

      def parse_public_url!(value)
        url = URI.parse(value)
        valid = url.is_a?(URI::HTTPS) &&
          url.host.present? &&
          url.userinfo.nil? &&
          url.query.nil? &&
          url.fragment.nil? &&
          [ "", "/" ].include?(url.path.to_s)

        unless valid
          raise InvalidConfiguration,
            "MCWEB_PUBLIC_URL must be an HTTPS origin without credentials, path, query, or fragment"
        end

        reject_placeholder_host!(url.host, "MCWEB_PUBLIC_URL")
        url.freeze
      rescue URI::InvalidURIError
        raise InvalidConfiguration, "MCWEB_PUBLIC_URL must be a valid HTTPS origin"
      end

      def allowed_hosts(environment, public_host)
        values = [ public_host ]
        values.concat(environment.fetch("MCWEB_ALLOWED_HOSTS", "").split(","))

        values.filter_map { |value| value.to_s.strip.presence }.uniq.tap do |hosts|
          hosts.each { |host| validate_host!(host, "MCWEB_ALLOWED_HOSTS") }
        end.freeze
      end

      def validate_host!(host, key)
        return if valid_ip_address?(host)
        return if host.match?(/\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i)

        raise InvalidConfiguration, "#{key} must contain only exact host names or IP addresses"
      end

      def trusted_proxies(environment)
        raw = environment.fetch("MCWEB_TRUSTED_PROXIES", "127.0.0.1/32,::1/128")
        ranges = raw.split(",").filter_map { |value| value.strip.presence }.map do |value|
          IPAddr.new(value)
        rescue IPAddr::InvalidAddressError
          raise InvalidConfiguration, "MCWEB_TRUSTED_PROXIES must contain valid IP addresses or CIDR ranges"
        end

        raise InvalidConfiguration, "MCWEB_TRUSTED_PROXIES must not be empty" if ranges.empty?

        if ranges.any? { |range| UNIVERSAL_PROXY_RANGES.include?(range) }
          raise InvalidConfiguration, "MCWEB_TRUSTED_PROXIES must not trust the entire Internet"
        end

        ranges.freeze
      end

      def smtp_settings(environment, public_host)
        address = required!(environment, "MCWEB_SMTP_ADDRESS")
        validate_host!(address, "MCWEB_SMTP_ADDRESS")
        reject_placeholder_host!(address, "MCWEB_SMTP_ADDRESS")
        port = integer!(environment.fetch("MCWEB_SMTP_PORT", "587"), "MCWEB_SMTP_PORT", range: 1..65_535)
        authentication = environment.fetch("MCWEB_SMTP_AUTHENTICATION", "plain").downcase
        unless SMTP_AUTHENTICATIONS.include?(authentication)
          raise InvalidConfiguration, "MCWEB_SMTP_AUTHENTICATION must be plain, login, cram_md5, or none"
        end

        user_name = environment.fetch("MCWEB_SMTP_USERNAME", "").presence
        password = environment.fetch("MCWEB_SMTP_PASSWORD", "").presence
        if authentication == "none"
          if user_name || password
            raise InvalidConfiguration, "SMTP credentials must be empty when MCWEB_SMTP_AUTHENTICATION=none"
          end
        elsif user_name.nil? || password.nil?
          raise InvalidConfiguration, "MCWEB_SMTP_USERNAME and MCWEB_SMTP_PASSWORD are required for authenticated SMTP"
        end
        reject_placeholder_value!(user_name, "MCWEB_SMTP_USERNAME") if user_name
        reject_placeholder_value!(password, "MCWEB_SMTP_PASSWORD") if password

        tls_mode = environment.fetch("MCWEB_SMTP_TLS", "starttls").downcase
        unless SMTP_TLS_MODES.include?(tls_mode)
          raise InvalidConfiguration, "MCWEB_SMTP_TLS must be starttls or tls"
        end

        helo_domain = environment.fetch("MCWEB_SMTP_HELO_DOMAIN", public_host).presence || public_host
        validate_host!(helo_domain, "MCWEB_SMTP_HELO_DOMAIN")

        {
          address: address,
          port: port,
          domain: helo_domain,
          user_name: user_name,
          password: password,
          authentication: authentication == "none" ? nil : authentication.to_sym,
          enable_starttls_auto: tls_mode == "starttls",
          ssl: tls_mode == "tls",
          open_timeout: integer!(environment.fetch("MCWEB_SMTP_OPEN_TIMEOUT", "5"), "MCWEB_SMTP_OPEN_TIMEOUT", range: 1..60),
          read_timeout: integer!(environment.fetch("MCWEB_SMTP_READ_TIMEOUT", "10"), "MCWEB_SMTP_READ_TIMEOUT", range: 1..120)
        }.compact.freeze
      end

      def mail_from(environment)
        value = required!(environment, "MCWEB_MAIL_FROM")
        address = Mail::Address.new(value)
        unless address.address.present? && address.address.match?(URI::MailTo::EMAIL_REGEXP)
          raise InvalidConfiguration, "MCWEB_MAIL_FROM must contain a valid email address"
        end

        reject_placeholder_host!(address.domain, "MCWEB_MAIL_FROM")
        value
      rescue Mail::Field::ParseError
        raise InvalidConfiguration, "MCWEB_MAIL_FROM must contain a valid email address"
      end

      def storage_service(environment)
        service = environment.fetch("MCWEB_ACTIVE_STORAGE_SERVICE", "private_s3")
        unless service == "private_s3"
          raise InvalidConfiguration, "MCWEB_ACTIVE_STORAGE_SERVICE must be private_s3 in production"
        end

        bucket = required!(environment, "MCWEB_S3_BUCKET")
        if bucket.start_with?("replace_with", "replace-with")
          raise InvalidConfiguration, "MCWEB_S3_BUCKET must not use a placeholder value"
        end
        required!(environment, "MCWEB_S3_REGION")
        validate_s3_endpoint!(environment["MCWEB_S3_ENDPOINT"])

        access_key = environment.fetch("MCWEB_S3_ACCESS_KEY_ID", "").presence
        secret_key = environment.fetch("MCWEB_S3_SECRET_ACCESS_KEY", "").presence
        if access_key.nil? != secret_key.nil?
          raise InvalidConfiguration,
            "MCWEB_S3_ACCESS_KEY_ID and MCWEB_S3_SECRET_ACCESS_KEY must be set together or both omitted for an IAM role"
        end
        reject_placeholder_value!(access_key, "MCWEB_S3_ACCESS_KEY_ID") if access_key
        reject_placeholder_value!(secret_key, "MCWEB_S3_SECRET_ACCESS_KEY") if secret_key

        boolean!(environment.fetch("MCWEB_S3_FORCE_PATH_STYLE", "0"), "MCWEB_S3_FORCE_PATH_STYLE")
        :private_s3
      end

      def validate_s3_endpoint!(value)
        return if value.blank?

        endpoint = URI.parse(value)
        valid = endpoint.is_a?(URI::HTTPS) &&
          endpoint.host.present? &&
          endpoint.userinfo.nil? &&
          endpoint.query.nil? &&
          endpoint.fragment.nil? &&
          [ "", "/" ].include?(endpoint.path.to_s)
        if valid
          reject_placeholder_host!(endpoint.host, "MCWEB_S3_ENDPOINT")
          return
        end

        raise InvalidConfiguration, "MCWEB_S3_ENDPOINT must be an HTTPS origin"
      rescue URI::InvalidURIError
        raise InvalidConfiguration, "MCWEB_S3_ENDPOINT must be a valid HTTPS origin"
      end

      def required!(environment, key)
        environment.fetch(key, "").to_s.strip.presence ||
          raise(InvalidConfiguration, "#{key} is required in production")
      end

      def integer!(value, key, range:)
        integer = Integer(value, 10)
        return integer if range.cover?(integer)

        raise InvalidConfiguration, "#{key} must be between #{range.begin} and #{range.end}"
      rescue ArgumentError
        raise InvalidConfiguration, "#{key} must be an integer"
      end

      def boolean!(value, key)
        normalized = value.to_s.downcase
        return true if TRUTHY_VALUES.include?(normalized)
        return false if FALSY_VALUES.include?(normalized)

        raise InvalidConfiguration, "#{key} must be a boolean"
      end

      def valid_ip_address?(value)
        IPAddr.new(value)
        true
      rescue IPAddr::InvalidAddressError
        false
      end

      def reject_placeholder_host!(host, key)
        normalized = host.to_s.downcase
        return unless normalized == "localhost" ||
          normalized == "example.com" ||
          normalized.end_with?(".example.com", ".example", ".invalid", ".test")

        raise InvalidConfiguration, "#{key} must not use a placeholder or development host"
      end

      def reject_placeholder_value!(value, key)
        normalized = value.to_s.strip.downcase
        placeholder = normalized.start_with?(
          "change_me",
          "change-me",
          "replace_with",
          "replace-with",
          "generate_with",
          "generate-with",
          "generate_",
          "generate-",
          "your_",
          "your-"
        )
        return unless placeholder || normalized.in?(%w[example placeholder])

        raise InvalidConfiguration, "#{key} must not use a placeholder value"
      end
    end
  end
end
