# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class FinanceAdminTest < ActionDispatch::IntegrationTest
    setup do
      SiteSetting.set("store.tax_rate_bps", "900")
      @owner = create_user(account_type: "owner")
      @customer = create_user
      @document = create_invoice
      sign_in_as(@owner)
    end

    test "finance workbench exposes filters, deep links, permissions, and retention rules" do
      get admin_store_finance_path(currency: "CNY", channel: "fake", tax_rate_bps: 900)

      assert_response :success
      assert_equal "Admin/Store/Finance/Index", inertia.component
      props = inertia.props.deep_symbolize_keys
      assert_equal 1, props.dig(:summary, :documents)
      assert_equal @document.public_id, props.dig(:documents, 0, :id)
      assert_equal @document.order.order_number, props.dig(:documents, 0, :order, :number)
      assert props.dig(:permissions, :createExports)
      assert props.dig(:permissions, :downloadExports)
      assert_equal 72, props.dig(:retention, :export_files, :file_hours)
      assert_equal admin_store_finance_exports_path, props.dig(:paths, :createExport)
      assert_equal "private, no-store", response.headers["Cache-Control"]
    end

    test "staff without finance read permission cannot infer the workbench" do
      sign_out
      staff = create_user(account_type: "staff")
      grant_admin_module(staff, "store")
      sign_in_as(staff)

      get admin_store_finance_path

      assert_redirected_to root_path
    end

    test "separate download permission is required" do
      finance_export = create_completed_export(expires_at: 1.hour.from_now)
      sign_out
      staff = create_user(account_type: "staff")
      grant_admin_module(staff, "store")
      grant_permission(staff, "store.finance.read")
      sign_in_as(staff)

      get admin_store_finance_export_download_path(finance_export)

      assert_redirected_to root_path
    end

    test "expired download becomes gone and cannot return file bytes" do
      finance_export = create_completed_export(expires_at: 1.minute.ago)

      get admin_store_finance_export_download_path(finance_export), as: :json

      assert_response :gone
      assert_equal "finance_export_unavailable", response.parsed_body.fetch("code", "finance_export_unavailable")
      assert finance_export.reload.expired?
      assert_not_equal "text/csv", response.media_type
    end

    test "export endpoint is idempotent and returns accepted JSON" do
      request_id = SecureRandom.uuid
      payload = {
        finance_export: {
          idempotency_key: request_id,
          filters: { currency: "CNY", channel: "fake" }
        }
      }

      post admin_store_finance_exports_path, params: payload, as: :json
      assert_response :accepted
      first_id = response.parsed_body.dig("finance_export", "id")

      post admin_store_finance_exports_path, params: payload, as: :json
      assert_response :accepted
      assert_equal first_id, response.parsed_body.dig("finance_export", "id")
      assert response.parsed_body.fetch("replayed")
    end

    private

    def sign_out
      delete identity_session_path
      assert_response :redirect
    end

    def create_invoice
      suffix = SecureRandom.hex(6)
      order = Commerce::Order.create!(
        public_id: "ord_admin_fin_#{suffix}",
        order_number: "AFIN#{suffix.upcase}",
        user: @customer,
        status: "paid",
        subtotal_cents: 3_000,
        total_cents: 3_000,
        currency: "CNY"
      )
      Commerce::OrderItem.create!(
        order:,
        product_name: "Admin finance item",
        quantity: 1,
        unit_price_cents: 3_000,
        total_cents: 3_000
      )
      payment = Payments::Record.create!(
        order:,
        provider: "fake",
        status: "succeeded",
        amount_cents: 3_000,
        currency: "CNY",
        provider_payment_id: "admin_finance_payment_#{suffix}"
      )
      Commerce::IssueFinanceInvoice.call(order:, payment_record: payment).value.fetch(:document)
    end

    def create_completed_export(expires_at:)
      finance_export = Commerce::FinanceExport.create!(
        requested_by: @owner,
        status: "completed",
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
end
