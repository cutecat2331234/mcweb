# frozen_string_literal: true

module Identity
  module AccountClosure
    class Contribution
      STATUSES = %w[ready blocked completed compensated failed].freeze

      attr_reader :status, :code, :details, :compensation_data

      def self.ready(details: {})
        new(status: "ready", details:)
      end

      def self.blocked(code:, details: {})
        new(status: "blocked", code:, details:)
      end

      def self.completed(details: {}, compensation_data: nil)
        new(status: "completed", details:, compensation_data:)
      end

      def self.compensated(details: {})
        new(status: "compensated", details:)
      end

      def self.failed(code:, details: {})
        new(status: "failed", code:, details:)
      end

      def initialize(status:, code: nil, details: {}, compensation_data: nil)
        normalized_status = status.to_s
        raise ArgumentError, "account_closure_contribution_status_invalid" unless normalized_status.in?(STATUSES)

        @status = normalized_status.freeze
        @code = code&.to_s&.freeze
        @details = details.to_h.deep_stringify_keys.freeze
        @compensation_data = compensation_data
      end

      def ready?
        status == "ready"
      end

      def blocked?
        status == "blocked"
      end

      def completed?
        status == "completed"
      end

      def public_payload
        { "status" => status, "code" => code, "details" => details }.compact
      end
    end
  end
end
