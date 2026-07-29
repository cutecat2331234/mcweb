module Commerce
  class Fulfillment < ApplicationRecord
    ERROR_CODE_FORMAT = /\A[a-z0-9_.-]{1,100}\z/
    SAFE_RESULT_KEYS = %w[success status error_code simulated external_reference].freeze

    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id
    belongs_to :order_item, class_name: "Commerce::OrderItem", foreign_key: :store_order_item_id
    has_many :attempts, class_name: "Commerce::FulfillmentAttempt", foreign_key: :store_fulfillment_id, dependent: :destroy
    has_many :connector_tasks, class_name: "Minecraft::ConnectorTask", foreign_key: :store_fulfillment_id, dependent: :nullify

    enum :status, {
      pending: "pending",
      processing: "processing",
      fulfilled: "fulfilled",
      failed: "failed",
      cancelled: "cancelled"
    }, validate: true

    validates :delivery_id, presence: true, uniqueness: true
    validates :max_attempts, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }

    before_validation :generate_delivery_id, on: :create

    def mark_fulfilled!(attempt: nil, result: {})
      with_lock do
        return if fulfilled? || cancelled?

        attempt = locked_attempt(attempt) if attempt
        return if attempt && !%w[pending processing].include?(attempt.status)

        attempt ||= current_dispatch_attempt
        summary = self.class.safe_result_summary(result).merge("success" => true)
        attempt&.update!(
          status: "succeeded",
          completed_at: Time.current,
          result_summary: summary,
          response_data: {}
        )
        update!(
          status: :fulfilled,
          fulfilled_at: Time.current,
          next_attempt_at: nil,
          last_error: nil,
          last_result_summary: summary
        )
        Commerce::DomainEvents.publish_after_commit(
          "commerce.fulfillment.completed",
          Commerce::DomainEvents.fulfillment(self, attempt:, result: summary)
        )
      end
    end

    def mark_failed!(error:, attempt: nil, result: {}, retryable: true)
      with_lock do
        return if fulfilled? || cancelled?

        existing_attempt = attempt ? locked_attempt(attempt) : current_dispatch_attempt
        return if attempt && (
          existing_attempt.nil? ||
          !%w[pending processing].include?(existing_attempt.status)
        )

        attempt = existing_attempt || create_dispatch_attempt_locked!
        completed_attempts = existing_attempt ? attempts_count : attempts_count + 1
        completed_attempts = max_attempts unless retryable
        error_code = self.class.normalize_error_code(error)
        next_attempt =
          if retryable && completed_attempts < max_attempts
            retry_delay(completed_attempts).from_now
          end
        summary = self.class.safe_result_summary(result).merge(
          "success" => false,
          "error_code" => error_code
        )
        attempt.update!(
          status: "failed",
          error_code: error_code,
          completed_at: Time.current,
          next_retry_at: next_attempt,
          result_summary: summary,
          response_data: {}
        )
        update!(
          status: :failed,
          attempts_count: completed_attempts,
          last_error: error_code,
          next_attempt_at: next_attempt,
          last_result_summary: summary
        )
        event = next_attempt ? "commerce.fulfillment.retryable_failed" : "commerce.fulfillment.failed"
        Commerce::DomainEvents.publish_after_commit(
          event,
          Commerce::DomainEvents.fulfillment(self, attempt:, result: summary)
        )
      end
    end

    def retryable?
      (pending? || failed?) && attempts_count < max_attempts &&
        !order.cancelled? && !order.refunded?
    end

    def exhausted?
      failed? && attempts_count >= max_attempts
    end

    def retry_delay(completed_attempts = attempts_count)
      [ 2**[ completed_attempts, 8 ].min, 300 ].min.minutes
    end

    def begin_dispatch_attempt!(trigger: "automatic", actor: nil, reason: nil, request_id: nil)
      with_lock do
        return current_dispatch_attempt if processing? && current_dispatch_attempt
        raise ActiveRecord::RecordInvalid, self unless retryable?

        create_dispatch_attempt_locked!(
          trigger: trigger,
          actor: actor,
          reason: reason,
          request_id: request_id
        ).tap do |attempt|
          update!(
            status: :processing,
            attempts_count: attempts_count + 1,
            next_attempt_at: nil,
            last_error: nil
          )
          Commerce::DomainEvents.publish_after_commit(
            "commerce.fulfillment.dispatched",
            Commerce::DomainEvents.fulfillment(self, attempt:)
          )
        end
      end
    end

    def current_dispatch_attempt
      attempts.where(action: "dispatch", status: %w[pending processing]).order(attempt_number: :desc).first
    end

    def self.normalize_error_code(error)
      value = error.to_s.strip.downcase
        .gsub(/[^a-z0-9_.-]+/, "_")
        .gsub(/\A_+|_+\z/, "")
        .first(100)
      ERROR_CODE_FORMAT.match?(value) ? value : "fulfillment_failed"
    end

    def self.safe_result_summary(result)
      value = result.respond_to?(:to_h) ? result.to_h : {}
      value = value.stringify_keys.slice(*SAFE_RESULT_KEYS)
      value["error_code"] = normalize_error_code(value["error_code"]) if value["error_code"].present?
      value.transform_values do |entry|
        case entry
        when true, false, Numeric, NilClass
          entry
        else
          entry.to_s.first(200)
        end
      end
    end

    private

    def locked_attempt(attempt)
      attempts.lock.find_by(id: attempt.id)
    end

    def create_dispatch_attempt_locked!(trigger: "automatic", actor: nil, reason: nil, request_id: nil)
      attempt_number = [ attempts.maximum(:attempt_number).to_i, attempts_count ].max + 1
      attempts.create!(
        attempt_number: attempt_number,
        idempotency_key: "fulfillment-dispatch:#{delivery_id}:#{attempt_number}",
        trigger: trigger,
        action: "dispatch",
        status: "processing",
        actor: actor,
        reason: reason,
        request_id: request_id,
        started_at: Time.current,
        request_data: {},
        response_data: {},
        result_summary: {}
      )
    end

    def generate_delivery_id
      self.delivery_id ||= SecureRandom.uuid
    end
  end
end
