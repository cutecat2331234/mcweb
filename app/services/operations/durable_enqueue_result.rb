# frozen_string_literal: true

module Operations
  class DurableEnqueueResult
    STATUSES = %w[succeeded skipped].freeze

    attr_reader :status, :error_code, :metadata

    def self.succeeded(metadata: {})
      new(status: "succeeded", metadata:)
    end

    def self.skipped(error_code:, metadata: {})
      new(status: "skipped", error_code:, metadata:)
    end

    def initialize(status:, error_code: nil, metadata: {})
      @status = status.to_s
      @error_code = error_code&.to_s
      @metadata = metadata.to_h.deep_stringify_keys.freeze
      raise ArgumentError, "durable_enqueue_result_status_invalid" unless @status.in?(STATUSES)
      if @status == "skipped" && @error_code.blank?
        raise ArgumentError, "durable_enqueue_result_error_required"
      end
      if @status == "succeeded" && @error_code.present?
        raise ArgumentError, "durable_enqueue_result_error_forbidden"
      end
      if ActiveSupport::JSON.encode(@metadata).bytesize > 4.kilobytes
        raise ArgumentError, "durable_enqueue_result_metadata_too_large"
      end
    end
  end
end
