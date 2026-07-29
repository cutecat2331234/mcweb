# frozen_string_literal: true

require "test_helper"

class Commerce::FinanceExportsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    SiteSetting.set("store.tax_rate_bps", "600")
    @customer = create_user
    @owner = create_user(account_type: "owner")
    @document = create_invoice
  end

  test "export request enforces independent permission and idempotency fingerprint" do
    denied_actor = create_user
    request_id = SecureRandom.uuid
    denied = Commerce::RequestFinanceExport.call(
      actor: denied_actor,
      filters: { currency: "CNY" },
      idempotency_key: request_id
    )

    assert_predicate denied, :failure?
    assert_equal "finance_export_unauthorized", denied.code

    first = Commerce::RequestFinanceExport.call(
      actor: @owner,
      filters: { currency: "CNY", channel: "fake" },
      idempotency_key: request_id
    )
    replay = Commerce::RequestFinanceExport.call(
      actor: @owner,
      filters: { channel: "fake", currency: "CNY" },
      idempotency_key: request_id
    )
    conflict = Commerce::RequestFinanceExport.call(
      actor: @owner,
      filters: { currency: "USD" },
      idempotency_key: request_id
    )

    assert_predicate first, :success?, first.error
    assert_predicate replay, :success?, replay.error
    assert replay.value.fetch(:replayed)
    assert_equal first.value.fetch(:finance_export).id, replay.value.fetch(:finance_export).id
    assert_predicate conflict, :failure?
    assert_equal "finance_export_idempotency_conflict", conflict.code
    assert_equal 1, Commerce::FinanceExport.where(requested_by: @owner, idempotency_key: request_id).count
  end

  test "asynchronous export builds filtered CSV with progress, digest, and immutable audit" do
    request_id = SecureRandom.uuid
    result = Commerce::RequestFinanceExport.call(
      actor: @owner,
      filters: {
        currency: "CNY",
        channel: "fake",
        tax_country: "CN",
        tax_rate_bps: 600
      },
      idempotency_key: request_id
    )
    assert_predicate result, :success?, result.error
    finance_export = result.value.fetch(:finance_export)

    perform_enqueued_jobs(only: Commerce::BuildFinanceExportJob)

    finance_export.reload
    assert finance_export.completed?
    assert_equal 100, finance_export.progress_percent
    assert_equal 1, finance_export.row_count
    assert finance_export.file.attached?
    assert_match @document.document_number, finance_export.file.download
    assert_match "tax_rate_bps", finance_export.file.download
    assert_match(/\A[0-9a-f]{64}\z/, finance_export.file_sha256)
    assert finance_export.expires_at.future?
    assert_equal %w[queued running completed], finance_export.events.order(:id).pluck(:status)
    assert_equal 1, AuditLog.where(action: "commerce.finance_export_requested", request_id: request_id).count
    assert_equal 1, AuditLog.where(action: "commerce.finance_export_completed", request_id: request_id).count
  end

  test "worker fails closed if export permission was removed after enqueue" do
    actor = create_user(account_type: "staff")
    grant_admin_module(actor, "store")
    grant_permission(actor, "store.finance.read")
    grant_permission(actor, "store.finance.exports.create")
    result = Commerce::RequestFinanceExport.call(
      actor:,
      filters: {},
      idempotency_key: SecureRandom.uuid
    )
    assert_predicate result, :success?, result.error
    finance_export = result.value.fetch(:finance_export)

    actor.user_roles.destroy_all
    Commerce::BuildFinanceExportJob.perform_now(finance_export.id)

    assert finance_export.reload.failed?
    assert_equal "finance_export_permission_revoked", finance_export.error_code
    assert_not finance_export.file.attached?
  end

  test "expired files fail download authorization and are purged without deleting audit metadata" do
    finance_export = create_completed_export(expires_at: 1.minute.ago)

    authorization = Commerce::AuthorizeFinanceExportDownload.call(
      finance_export:,
      actor: @owner
    )
    perform_enqueued_jobs

    assert_predicate authorization, :failure?
    assert_equal "finance_export_unavailable", authorization.code
    assert finance_export.reload.expired?
    assert Commerce::FinanceExport.exists?(finance_export.id)
    assert_equal 1, AuditLog.where(
      action: "commerce.finance_export_expired",
      resource_type: "Commerce::FinanceExport",
      resource_id: finance_export.id
    ).count
  end

  test "download authorization is scoped to the export requester" do
    finance_export = create_completed_export(expires_at: 1.hour.from_now)
    other_owner = create_user(account_type: "owner")

    authorization = Commerce::AuthorizeFinanceExportDownload.call(
      finance_export:,
      actor: other_owner
    )

    assert_predicate authorization, :failure?
    assert_equal "finance_export_unauthorized", authorization.code
    assert_equal 0, AuditLog.where(
      action: "commerce.finance_export_downloaded",
      resource_type: "Commerce::FinanceExport",
      resource_id: finance_export.id
    ).count
  end

  test "CSV neutralizes spreadsheet formulas in text dimensions" do
    SiteSetting.set("store.tax_region", "=HYPERLINK(\"https://invalid.example\")")
    dangerous_document = create_invoice

    generated = Commerce::FinanceCsvExport.call(
      filters: { currency: dangerous_document.currency }
    )

    assert_predicate generated, :success?, generated.error
    csv = generated.value.fetch(:io).read
    assert_includes csv, "'=HYPERLINK"
    assert_not_includes csv, ",=HYPERLINK"
  end

  private

  def create_invoice
    suffix = SecureRandom.hex(6)
    order = Commerce::Order.create!(
      public_id: "ord_export_#{suffix}",
      order_number: "EXP#{suffix.upcase}",
      user: @customer,
      status: "paid",
      subtotal_cents: 2_000,
      total_cents: 2_000,
      currency: "CNY"
    )
    Commerce::OrderItem.create!(
      order:,
      product_name: "Export item",
      quantity: 1,
      unit_price_cents: 2_000,
      total_cents: 2_000
    )
    payment = Payments::Record.create!(
      order:,
      provider: "fake",
      status: "succeeded",
      amount_cents: 2_000,
      currency: "CNY",
      provider_payment_id: "export_payment_#{suffix}"
    )
    Commerce::IssueFinanceInvoice.call(order:, payment_record: payment).value.fetch(:document)
  end

  def create_completed_export(expires_at:)
    finance_export = Commerce::FinanceExport.create!(
      requested_by: @owner,
      status: "completed",
      format: "csv",
      idempotency_key: SecureRandom.uuid,
      filters_digest: Digest::SHA256.hexdigest("{}"),
      filters: {},
      progress_percent: 100,
      row_count: 1,
      requested_at: 2.hours.ago,
      started_at: 2.hours.ago,
      completed_at: 90.minutes.ago,
      expires_at:,
      retention_until: 1.year.from_now,
      file_sha256: Digest::SHA256.hexdigest("finance")
    )
    finance_export.file.attach(
      io: StringIO.new("document_number\n#{@document.document_number}\n"),
      filename: "finance.csv",
      content_type: "text/csv"
    )
    finance_export
  end
end
