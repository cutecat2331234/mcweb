# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"
require "tempfile"

class CommerceCustomerDisputesTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @other = create_user
    @staff = create_user
    @order = Commerce::Order.create!(
      user: @owner,
      status: "completed",
      subtotal_cents: 1_000,
      total_cents: 1_000,
      currency: "CNY"
    )
    @payment = Payments::Record.create!(
      order: @order,
      provider: "fake",
      provider_payment_id: "customer_route_#{SecureRandom.hex(8)}",
      status: "succeeded",
      amount_cents: 1_000,
      currency: "CNY"
    )
  end

  test "order owner can create view and conditionally withdraw a payment dispute" do
    sign_in_as(@owner)
    create_request_id = SecureRandom.uuid

    post store_order_disputes_path(@order), params: {
      dispute: {
        request_id: create_request_id,
        reason_kind: "unauthorized",
        description: "This payment was not authorized by me.",
        amount_cents: 700
      }
    }

    assert_redirected_to store_order_path(@order)
    dispute = @order.disputes.customer_origin.find_by!(customer_opened_by: @owner)

    get store_order_path(@order)
    assert_response :success
    props = inertia.props.deep_symbolize_keys.fetch(:paymentDisputes)
    item = props.fetch(:cases).find { |entry| entry[:public_id] == dispute.public_id }
    assert item
    assert_equal true, item.fetch(:can_withdraw)
    assert_equal true, item.fetch(:can_upload_evidence)
    assert_equal store_order_dispute_path(@order, dispute), item.fetch(:withdraw_url)
    assert_equal "This payment was not authorized by me.",
      item.fetch(:timeline).find { |event| event[:description].present? }.fetch(:description)

    delete store_order_dispute_path(@order, dispute), params: {
      dispute: {
        request_id: SecureRandom.uuid,
        withdraw_reason: "Opened by mistake"
      }
    }

    assert_redirected_to store_order_path(@order)
    assert dispute.reload.withdrawn?
  end

  test "another account cannot enumerate order-scoped create or withdrawal routes" do
    dispute = create_customer_dispute
    sign_in_as(@other)

    post store_order_disputes_path(@order), params: {
      dispute: {
        request_id: SecureRandom.uuid,
        reason_kind: "other",
        description: "Trying to open a case on someone else's order.",
        amount_cents: 100
      }
    }
    assert_response :not_found

    delete store_order_dispute_path(@order, dispute), params: {
      dispute: { request_id: SecureRandom.uuid }
    }
    assert_response :not_found
    assert dispute.reload.open?
  end

  test "customer order props never reuse staff dispute notes or sensitive evidence" do
    dispute = create_customer_dispute
    dispute.update!(
      assigned_to: @staff,
      risk_level: "critical",
      provider_dispute_id: "provider-secret-case-reference"
    )
    internal_note = "STAFF-INTERNAL-NOTE-#{SecureRandom.hex(6)}"
    metadata_secret = "RAW-METADATA-#{SecureRandom.hex(6)}"
    Commerce::DisputeEvent.create!(
      dispute:,
      actor: @staff,
      idempotency_key: "staff-note-#{SecureRandom.uuid}",
      request_id: "staff-request-#{SecureRandom.uuid}",
      source: "manual",
      event_type: "note",
      from_status: dispute.status,
      to_status: dispute.status,
      note: internal_note,
      metadata: { "internal_secret" => metadata_secret }
    )
    Commerce::DisputeEvidence.create!(
      dispute:,
      submitted_by: @staff,
      idempotency_key: "legacy-evidence-#{SecureRandom.uuid}",
      title: "STAFF-EVIDENCE-TITLE",
      filename: "staff-only.txt",
      content_type: "text/plain",
      content: "STAFF-EVIDENCE-CONTENT",
      byte_size: 22,
      sha256: Digest::SHA256.hexdigest("STAFF-EVIDENCE-CONTENT"),
      submission_status: "submitted",
      submitted_at: Time.current
    )
    sign_in_as(@owner)

    get store_order_path(@order)

    assert_response :success
    serialized = inertia.props.deep_symbolize_keys.fetch(:paymentDisputes).to_json
    assert_includes serialized, dispute.public_id
    assert_includes serialized, "The payment was not authorized by me."
    refute_includes serialized, internal_note
    refute_includes serialized, metadata_secret
    refute_includes serialized, @staff.username
    refute_includes serialized, "staff-request-"
    refute_includes serialized, "provider-secret-case-reference"
    refute_includes serialized, @payment.provider_payment_id
    refute_includes serialized, "critical"
    refute_includes serialized, "STAFF-EVIDENCE-TITLE"
    refute_includes serialized, "STAFF-EVIDENCE-CONTENT"
  end

  test "customer SecureEvidence responses omit the retained integrity hash" do
    dispute = create_customer_dispute
    sign_in_as(@owner)

    post secure_evidence_attachments_path, params: {
      subject_key: Commerce::SecureEvidenceSubjects::SUBJECT_KEY,
      subject_public_id: dispute.public_id,
      idempotency_key: "customer-dispute-api-#{SecureRandom.hex(8)}",
      file: uploaded_evidence("customer evidence")
    }

    assert_response :created
    payload = response.parsed_body
    refute payload.key?("sha256")

    get scan_status_secure_evidence_attachment_path(payload.fetch("public_id"))
    assert_response :ok
    refute response.parsed_body.key?("sha256")
  ensure
    @temporary_file&.close!
  end

  test "an active dispute blocks old download tokens until its hold is restored" do
    product = Commerce::Product.create!(
      name: "Dispute protected download",
      slug: "dispute-protected-download-#{SecureRandom.hex(5)}",
      product_type: "digital",
      status: "active",
      price_cents: 1_000,
      currency: "CNY"
    )
    item = Commerce::OrderItem.create!(
      order: @order,
      product:,
      product_name: product.name,
      unit_price_cents: 1_000,
      quantity: 1,
      total_cents: 1_000,
      fulfillment_snapshot: {
        "product_type" => "digital",
        "fulfillment_config" => {
          "download_url" => "https://example.com/customer-download"
        }
      }
    )
    token = Commerce::GenerateDownloadToken.call(
      order_item: item,
      user: @owner
    ).value.fetch(:token)
    dispute = create_customer_dispute
    sign_in_as(@owner)

    get store_download_path(token)
    assert_response :locked

    withdrawal = Commerce::Disputes::WithdrawCustomerDispute.call(
      order: @order,
      dispute:,
      actor: @owner,
      request_id: SecureRandom.uuid
    )
    assert_predicate withdrawal, :success?, withdrawal.error

    get store_download_path(token)
    assert_redirected_to "https://example.com/customer-download"
  end

  private

  def create_customer_dispute
    result = Commerce::Disputes::CreateCustomerDispute.call(
      order: @order,
      actor: @owner,
      request_id: SecureRandom.uuid,
      reason_kind: "unauthorized",
      description: "The payment was not authorized by me.",
      amount_cents: 700
    )
    assert result.success?, result.error
    result.value.fetch(:dispute)
  end

  def uploaded_evidence(content)
    @temporary_file&.close!
    @temporary_file = Tempfile.new([ "customer-dispute", ".txt" ])
    @temporary_file.binmode
    @temporary_file.write(content)
    @temporary_file.rewind
    Rack::Test::UploadedFile.new(
      @temporary_file.path,
      "text/plain",
      original_filename: "customer-evidence.txt"
    )
  end
end
