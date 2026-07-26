# frozen_string_literal: true

require "uri"
require_relative "error"
require_relative "../../developer_mode"

module Mcweb
  module Plugins
    module Marketplace
      class PackageSource
        MAX_LENGTH = 2_048
        ALLOWED_SCHEMES = %w[file https].freeze

        attr_reader :scheme, :canonical_url, :host

        def initialize(value)
          source = value.to_s
          raise SourceError, "package source is required" if source.empty?
          raise SourceError, "package source is too long" if source.bytesize > MAX_LENGTH
          raise SourceError, "package source contains control characters" if source.match?(/[[:cntrl:]]/)

          uri = URI.parse(source)
          @scheme = uri.scheme.to_s.downcase.freeze
          raise SourceError, "package source must use file or HTTPS" unless ALLOWED_SCHEMES.include?(scheme)
          if developer_mode_local_only? && scheme != "file"
            raise SourceError, "Developer Mode only permits local plugin packages"
          end
          raise SourceError, "package source must not contain credentials" if uri.userinfo

          validate_uri!(uri)
          uri.scheme = scheme
          uri.query = nil
          uri.fragment = nil
          @host = uri.host&.downcase&.freeze
          uri.host = host if host
          @canonical_url = uri.to_s.freeze
          freeze
        rescue URI::InvalidURIError
          raise SourceError, "package source is not a valid URI"
        end

        def to_h
          {
            scheme: scheme,
            url: canonical_url,
            host: host
          }.compact.freeze
        end

        private

        def developer_mode_local_only?
          Mcweb::DeveloperMode.enabled? &&
            Mcweb::DeveloperMode.integration(:plugin_marketplace) == :local_only
        end

        def validate_uri!(uri)
          if scheme == "https"
            raise SourceError, "HTTPS package source must include a host" if uri.host.to_s.empty?
            raise SourceError, "HTTPS package source must not include a port outside 1..65535" unless uri.port.between?(1, 65_535)
          elsif uri.path.to_s.empty?
            raise SourceError, "file package source must include a path"
          end
        rescue URI::InvalidComponentError
          raise SourceError, "package source contains an invalid component"
        end
      end
    end
  end
end
