# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class DisputesAdminTest < ActionDispatch::IntegrationTest
    setup do
      @owner = create_user(account_type: "owner")
      customer = create_user
      order = Commerce::Order.create!(
        user: customer,
        status: "completed",
        currency: "CNY",
        subtotal_cents: 1_000,
        total_cents: 1_000
      )
      @payment = Payments::Record.create!(
        order: order,
        provider: "fake",
        provider_payment_id: "fake_admin_dispute_#{SecureRandom.hex(6)}",
        status: "succeeded",
        amount_cents: 1_000,
        currency: "CNY"
      )
      result = Commerce::Disputes::ApplyChannelEvent.call(
        provider: "fake",
        provider_event_id: "evt-admin-dispute",
        provider_dispute_id: "dp-admin",
        payment_record: @payment,
        event_type: "dispute.created",
        provider_status: "needs_response",
        amount_cents: 500,
        currency: "CNY",
        occurred_at: Time.current,
        sequence: 1,
        evidence_due_at: 2.days.from_now,
        risk_level: "high",
        reason_code: "unrecognized"
      )
      @dispute = result.value.fetch(:dispute)
    end

    test "read-only support sees the workbench but not sensitive details or actions" do
      support = create_user
      grant_permission(support, "admin.access")
      grant_permission(support, "store.disputes.read")
      sign_in_as(support)

      get admin_store_disputes_path
      assert_response :success
      assert_equal "Admin/Store/Disputes/Index", inertia.component
      props = inertia.props.deep_symbolize_keys
      assert_not props.dig(:permissions, :sensitiveRead)
      assert_not props.dig(:permissions, :acceptLoss)

      get admin_store_dispute_path(@dispute), as: :json
      assert_response :success
      assert_nil response.parsed_body.dig("dispute", "sensitive")

      post execute_action_admin_store_dispute_path(@dispute),
           params: {
             action: "accept_loss",
             request_id: SecureRandom.uuid,
             reason: "Attempted without the independent permission.",
             expected_lock_version: @dispute.lock_version
           },
           as: :json
      assert_response :unprocessable_entity
      assert_equal "evidence_required", @dispute.reload.status
      refute @dispute.events.exists?(event_type: "accept_loss")
    end

    test "owner can load Drawer detail and an expired evidence download returns gone" do
      evidence = Commerce::DisputeEvidence.create!(
        dispute: @dispute,
        submitted_by: @owner,
        idempotency_key: "admin-evidence-#{SecureRandom.uuid}",
        title: "Provider response",
        filename: "provider-response.txt",
        content_type: "text/plain",
        content: "provider response",
        byte_size: "provider response".bytesize,
        sha256: Digest::SHA256.hexdigest("provider response"),
        submitted_at: Time.current
      )
      sign_in_as(@owner)

      get admin_store_dispute_path(@dispute), as: :json
      assert_response :success
      detail = response.parsed_body
      assert_equal @dispute.provider_dispute_id,
                   detail.dig("dispute", "sensitive", "providerDisputeId")
      assert detail.fetch("events").any?
      assert_equal evidence.public_id,
                   detail.fetch("evidence").first.fetch("publicId")

      post evidence_download_token_admin_store_dispute_path(
        @dispute,
        evidence_id: evidence.public_id
      ), as: :json
      assert_response :success
      download_url = response.parsed_body.fetch("url")

      travel 6.minutes do
        get download_url
        assert_response :gone
      end
    end
  end
end
