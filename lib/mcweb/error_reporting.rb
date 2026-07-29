# frozen_string_literal: true

require "digest"
require "json"

module Mcweb
  module ErrorReporting
    REDACTED = "[FILTERED]"
    MESSAGE_LIMIT = 1_000
    VALUE_LIMIT = 512
    CONTEXT_KEYS = %w[
      request_id controller action job_class queue_name provider event_type
      plugin_id error_code operation_id source
    ].freeze
    SENSITIVE_PATTERN =
      /(authorization|cookie|credential|email|otp|passw|secret|session|token|_key)/i
    INLINE_SECRET_PATTERN = /
      (?<key>authorization|cookie|credential|email|otp|passw(?:ord)?|secret|
      session|token|api[_-]?key)
      \s*[=:]\s*
      (?<value>[^\s,;]+)/ix
    URI_CREDENTIAL_PATTERN =
      %r{(?<scheme>[a-z][a-z0-9+.-]*://)[^/\s:@]+:[^@/\s]+@}i
    BEARER_PATTERN = /\bBearer\s+[A-Za-z0-9._~+\/=-]+/i
    EMAIL_PATTERN =
      /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i
    TOKEN_PATTERN = /\b(?:gh[pousr]_[A-Za-z0-9]{20,}|eyJ[A-Za-z0-9_-]{20,})\b/

    class LoggerAdapter
      def call(event)
        Rails.logger.error(
          "[mcweb.error_report] #{JSON.generate(event)}"
        )
      end
    end

    class Subscriber
      def report(error, handled:, severity:, context:, source:)
        ErrorReporting.deliver(
          error,
          handled:,
          severity:,
          context:,
          source:
        )
      rescue StandardError => adapter_error
        Rails.logger.warn(
          "[mcweb.error_report] adapter failed: #{adapter_error.class.name}"
        )
      end
    end

    class << self
      attr_writer :adapter

      def adapter
        @adapter ||= LoggerAdapter.new
      end

      def subscriber
        @subscriber ||= Subscriber.new
      end

      def deliver(error, handled:, severity:, context:, source:)
        adapter.call(
          build_event(
            error,
            handled:,
            severity:,
            context:,
            source:
          )
        )
      end

      def build_event(error, handled:, severity:, context:, source:)
        {
          error_class: error.class.name.to_s.slice(0, 191),
          message: sanitize_text(error.message),
          fingerprint: fingerprint(error),
          handled: handled == true,
          severity: normalize_severity(severity),
          source: source.to_s.slice(0, 191),
          context: sanitize_context(context)
        }.freeze
      end

      def sanitize_context(context)
        return {}.freeze unless context.respond_to?(:to_h)

        context.to_h.each_with_object({}) do |(raw_key, raw_value), result|
          key = raw_key.to_s
          next unless CONTEXT_KEYS.include?(key)

          result[key] = if key.match?(SENSITIVE_PATTERN)
            REDACTED
          else
            sanitize_value(raw_value)
          end
        end.sort.to_h.freeze
      rescue StandardError
        {}.freeze
      end

      def sanitize_text(value)
        value.to_s
          .encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
          .gsub(URI_CREDENTIAL_PATTERN) { "#{$~[:scheme]}#{REDACTED}@" }
          .gsub(BEARER_PATTERN, "Bearer #{REDACTED}")
          .gsub(EMAIL_PATTERN, REDACTED)
          .gsub(TOKEN_PATTERN, REDACTED)
          .gsub(INLINE_SECRET_PATTERN) { "#{$~[:key]}=#{REDACTED}" }
          .slice(0, MESSAGE_LIMIT)
      rescue StandardError
        "error message unavailable"
      end

      private

      def sanitize_value(value)
        case value
        when String, Symbol
          sanitize_text(value).slice(0, VALUE_LIMIT)
        when Numeric, TrueClass, FalseClass, NilClass
          value
        else
          value.respond_to?(:to_param) ?
            sanitize_text(value.to_param).slice(0, VALUE_LIMIT) :
            value.class.name.to_s.slice(0, VALUE_LIMIT)
        end
      end

      def normalize_severity(value)
        severity = value.to_s
        %w[debug info warning error fatal].include?(severity) ?
          severity :
          "error"
      end

      def fingerprint(error)
        application_frame = Array(error.backtrace).find do |line|
          line.include?("/app/") || line.include?("\\app\\")
        end
        frame = application_frame.to_s
          .gsub(%r{\A.*?(?=app[/\\])}, "")
          .slice(0, 512)
        Digest::SHA256.hexdigest(
          "#{error.class.name}\u0000#{frame}"
        )
      end
    end
  end
end
