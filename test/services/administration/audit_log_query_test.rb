# frozen_string_literal: true

require "test_helper"

module Administration
  class AuditLogQueryTest < ActiveSupport::TestCase
    setup do
      @alice = create_user(username: "audit_alice")
      @bob = create_user(username: "audit_bob")
      @resource = create_user(username: "audit_target")

      travel_to 3.days.ago do
        AuditLogger.call(
          actor: @alice,
          action: "identity.email_changed",
          resource: @resource,
          metadata: { request_id: "req-old" }
        )
      end
      travel_to 1.day.ago do
        AuditLogger.call(
          actor: @alice,
          action: "store.order.refunded",
          resource: @resource,
          request_id: "req-store"
        )
      end
      AuditLogger.call(
        actor: @bob,
        action: "identity.totp_disabled",
        resource: @resource,
        request_id: "req-current"
      )
    end

    test "filters by action family actor resource request and inclusive dates" do
      query = AuditLogQuery.new(
        filters: {
          action: "identity",
          actor: @alice.username,
          resource_type: "User",
          resource: @resource.public_id,
          request_id: "req-old",
          from: 4.days.ago.to_date.iso8601,
          to: 2.days.ago.to_date.iso8601
        }
      )

      assert_equal [ "identity.email_changed" ], query.records.pluck(:action)
      assert_equal 1, query.total
      assert_empty query.errors
    end

    test "request id is promoted from metadata for stable indexed lookup" do
      log = AuditLog.find_by!(action: "identity.email_changed")

      assert_equal "req-old", log.request_id
      assert_equal [ log.id ], AuditLogQuery.new(
        filters: { request_id: "req-old" }
      ).records.pluck(:id)
    end

    test "invalid dates fail visibly without broadening another valid filter" do
      query = AuditLogQuery.new(
        filters: {
          action: "store",
          from: "not-a-date"
        }
      )

      assert_equal [ "store.order.refunded" ], query.records.pluck(:action)
      assert_equal({ from: "invalid" }, query.errors)
    end

    test "pagination is bounded and stable" do
      fixture_scope = AuditLog.where(request_id: %w[req-old req-store req-current])
      query = AuditLogQuery.new(
        filters: {},
        scope: fixture_scope,
        page: 2,
        per_page: 1_000
      )

      assert_equal 100, query.per_page
      assert_equal 2, query.page
      assert_equal 3, query.total
      assert_empty query.records
    end
  end
end
