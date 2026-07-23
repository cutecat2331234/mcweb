# frozen_string_literal: true

module Administration
  # Generic outbound webhook subscription driven by the Mcweb::Events bus. Lets an
  # integration/plugin receive any catalog event (or all of them via "*") without
  # touching core code — the delivery counterpart to the in-process event bus.
  class WebhookSubscription < ApplicationRecord
    WILDCARD = "*"
    MAX_FAILURES = 10

    belongs_to :created_by, class_name: "User", optional: true

    validates :name, presence: true
    validates :url, presence: true
    validate :url_must_be_public
    validate :event_must_be_known

    scope :active, -> { where(active: true, disabled_at: nil) }

    # Active subscriptions that should receive the given event.
    def self.for_event(event)
      active.where(event: [ event.to_s, WILDCARD ])
    end

    def self.valid_events
      Mcweb::Events::CATALOG + [ WILDCARD ]
    end

    def active?
      self[:active] && disabled_at.nil?
    end

    # Record a delivery outcome; auto-disable after too many consecutive failures.
    # Uses update_columns so recording delivery metadata never re-runs validations
    # (e.g. URL format) on an otherwise-valid subscription.
    def record_result!(success:, status:)
      if success
        update_columns(last_delivered_at: Time.current, last_status: status.to_s, failure_count: 0, updated_at: Time.current)
      else
        new_count = failure_count + 1
        attrs = { last_delivered_at: Time.current, last_status: status.to_s, failure_count: new_count, updated_at: Time.current }
        attrs[:disabled_at] = Time.current if new_count >= MAX_FAILURES
        update_columns(attrs)
      end
    end

    private

    def url_must_be_public
      return if url.blank?

      errors.add(:url, :invalid) unless UrlSafety.public_http_url?(url)
    end

    def event_must_be_known
      return if event.blank?

      errors.add(:event, :inclusion) unless self.class.valid_events.include?(event)
    end
  end
end
