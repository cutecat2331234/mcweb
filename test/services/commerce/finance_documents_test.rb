# frozen_string_literal: true

require "test_helper"

class Commerce::FinanceDocumentsTest < ActiveSupport::TestCase
  setup do
    SiteSetting.set("store.tax_rate_bps", "1300")
    SiteSetting.set("store.tax_country", "CN")
    SiteSetting.set("store.tax_region", "Shanghai")
    @customer = create_user
    @owner = create_user(account_type: "owner")
  end

  test "captures one immutable tax snapshot and issues one stable invoice on replay" do
    order, payment = create_paid_order(gross_cents: 1_001)

    first_snapshot = Commerce::CaptureFinanceTaxSnapshot.call(order:, actor: @customer)
    replay_snapshot = Commerce::CaptureFinanceTaxSnapshot.call(order:, actor: @customer)

    assert_predicate first_snapshot, :success?, first_snapshot.error
    assert_predicate replay_snapshot, :success?, replay_snapshot.error
    snapshot = first_snapshot.value.fetch(:snapshot)
    assert_equal snapshot.id, replay_snapshot.value.fetch(:snapshot).id
    assert replay_snapshot.value.fetch(:idempotent)
    assert_equal 1_001, snapshot.taxable_base_cents + snapshot.tax_cents
    assert_equal 1_300, snapshot.tax_rate_bps
    assert_equal "CN", snapshot.jurisdiction_country
    assert_equal "Shanghai", snapshot.jurisdiction_region
    original_tax_cents = snapshot.tax_cents
    assert_raises(ActiveRecord::RecordInvalid) { snapshot.update!(tax_cents: 0) }
    assert_equal original_tax_cents, snapshot.reload.tax_cents

    first_invoice = Commerce::IssueFinanceInvoice.call(order:, payment_record: payment)
    replay_invoice = Commerce::IssueFinanceInvoice.call(order:, payment_record: payment)

    assert_predicate first_invoice, :success?, first_invoice.error
    assert_predicate replay_invoice, :success?, replay_invoice.error
    invoice = first_invoice.value.fetch(:document)
    assert_equal invoice.id, replay_invoice.value.fetch(:document).id
    assert_equal "INV-#{order.order_number}", invoice.document_number
    assert_equal 1, invoice.version
    assert_equal 1, Commerce::FinanceDocument.invoice.where(order:).count
    assert_equal 1, invoice.events.where(event_type: "issued").count
    assert_equal 1, AuditLog.where(
      action: "commerce.finance_invoice_issued",
      resource_type: "Commerce::FinanceDocument",
      resource_id: invoice.id
    ).count
  end

  test "rejects a changed order source instead of silently replacing its tax snapshot" do
    order, = create_paid_order(gross_cents: 1_001)
    captured = Commerce::CaptureFinanceTaxSnapshot.call(order:)
    assert_predicate captured, :success?, captured.error

    order.update!(subtotal_cents: 1_100, total_cents: 1_100)
    conflict = Commerce::CaptureFinanceTaxSnapshot.call(order: order.reload)

    assert_predicate conflict, :failure?
    assert_equal "finance_tax_snapshot_conflict", conflict.code
    assert_equal 1, Commerce::FinanceTaxSnapshot.where(order:).count
  end

  test "allocates multiple refund receipts by issuance order and conserves cumulative rounding" do
    order, payment = create_paid_order(gross_cents: 1_001)
    invoice_result = Commerce::IssueFinanceInvoice.call(order:, payment_record: payment)
    assert_predicate invoice_result, :success?, invoice_result.error
    invoice = invoice_result.value.fetch(:document)

    earlier_refund = create_completed_refund(order:, payment:, amount_cents: 333)
    later_refund = create_completed_refund(order:, payment:, amount_cents: 668)

    later_first = Commerce::IssueFinanceRefundReceipt.call(refund: later_refund, actor: @owner)
    earlier_second = Commerce::IssueFinanceRefundReceipt.call(refund: earlier_refund, actor: @owner)
    replay = Commerce::IssueFinanceRefundReceipt.call(refund: later_refund, actor: @owner)

    assert_predicate later_first, :success?, later_first.error
    assert_predicate earlier_second, :success?, earlier_second.error
    assert_predicate replay, :success?, replay.error
    assert replay.value.fetch(:idempotent)
    assert_equal later_first.value.fetch(:document).id, replay.value.fetch(:document).id

    receipts = Commerce::FinanceDocument.refund_receipt.issued.where(order:)
    assert_equal 2, receipts.count
    assert_equal 1_001, receipts.sum(:gross_amount_cents)
    assert_equal invoice.tax_amount_cents, receipts.sum(:tax_amount_cents)
    assert_equal invoice.net_amount_cents, receipts.sum(:net_amount_cents)
    assert_equal [ 1, 2 ],
      receipts.order(:issued_at, :id).map { |document| document.content_snapshot.dig("allocation", "allocation_sequence") }
  end

  test "concurrent invoice events converge on one stable document" do
    order, payment = create_paid_order(gross_cents: 2_500)
    ready = Queue.new
    gate = Queue.new
    results = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          gate.pop
          results << Commerce::IssueFinanceInvoice.call(
            order: Commerce::Order.find(order.id),
            payment_record: Payments::Record.find(payment.id)
          )
        end
      end
    end
    2.times { ready.pop }
    2.times { gate << true }
    threads.each(&:join)

    outcomes = 2.times.map { results.pop }
    assert outcomes.all?(&:success?), outcomes.map(&:error).inspect
    assert_equal 1, Commerce::FinanceDocument.invoice.where(store_order_id: order.id).count
    assert_equal 1, outcomes.map { |result| result.value.fetch(:document).id }.uniq.length
  end

  test "document revision requires its own permission and is replay safe" do
    order, payment = create_paid_order(gross_cents: 1_000)
    document = Commerce::IssueFinanceInvoice.call(order:, payment_record: payment).value.fetch(:document)
    denied_actor = create_user
    request_id = SecureRandom.uuid

    denied = Commerce::TransitionFinanceDocument.call(
      document:,
      actor: denied_actor,
      action: "revise",
      reason: "Correct the customer-facing legal entity name.",
      request_id:
    )
    assert_predicate denied, :failure?
    assert_equal "finance_document_unauthorized", denied.code

    first = Commerce::TransitionFinanceDocument.call(
      document:,
      actor: @owner,
      action: "revise",
      reason: "Correct the customer-facing legal entity name.",
      request_id:
    )
    replay = Commerce::TransitionFinanceDocument.call(
      document:,
      actor: @owner,
      action: "revise",
      reason: "Correct the customer-facing legal entity name.",
      request_id:
    )

    assert_predicate first, :success?, first.error
    assert_predicate replay, :success?, replay.error
    revised = first.value.fetch(:document)
    assert_equal revised.id, replay.value.fetch(:document).id
    assert replay.value.fetch(:replayed)
    assert document.reload.superseded?
    assert revised.issued?
    assert_equal document.document_number, revised.document_number
    assert_equal 2, revised.version
    assert_equal document, revised.supersedes
    assert_equal 1, AuditLog.where(action: "commerce.finance_document_revised", request_id: request_id).count
    assert_not revised.update(content_snapshot: { overwritten: true })
    assert_includes revised.errors[:base],
      I18n.t("mcweb.validation_errors.issued_finance_document_content_is_immutable")
  end

  test "voided documents remain terminal under payment and refund event replay" do
    order, payment = create_paid_order(gross_cents: 1_000)
    invoice = Commerce::IssueFinanceInvoice.call(order:, payment_record: payment).value.fetch(:document)
    invoice_void = Commerce::TransitionFinanceDocument.call(
      document: invoice,
      actor: @owner,
      action: "void",
      reason: "Void the test invoice after an external cancellation.",
      request_id: SecureRandom.uuid
    )
    assert_predicate invoice_void, :success?, invoice_void.error

    replayed_invoice = Commerce::IssueFinanceInvoice.call(order:, payment_record: payment)
    assert_predicate replayed_invoice, :success?, replayed_invoice.error
    assert replayed_invoice.value.fetch(:idempotent)
    assert replayed_invoice.value.fetch(:document).voided?
    assert_equal 1, Commerce::FinanceDocument.invoice.where(order:).count

    refund = create_completed_refund(order:, payment:, amount_cents: 400)
    receipt = Commerce::IssueFinanceRefundReceipt.call(refund:, actor: @owner).value.fetch(:document)
    receipt_void = Commerce::TransitionFinanceDocument.call(
      document: receipt,
      actor: @owner,
      action: "void",
      reason: "Void the test receipt while preserving its source refund.",
      request_id: SecureRandom.uuid
    )
    assert_predicate receipt_void, :success?, receipt_void.error

    replayed_receipt = Commerce::IssueFinanceRefundReceipt.call(refund:, actor: @owner)
    assert_predicate replayed_receipt, :success?, replayed_receipt.error
    assert replayed_receipt.value.fetch(:idempotent)
    assert replayed_receipt.value.fetch(:document).voided?
    assert_equal 1, Commerce::FinanceDocument.refund_receipt.where(refund:).count
  end

  test "voided refund receipts remain in cumulative tax allocation history" do
    order, payment = create_paid_order(gross_cents: 1_001)
    invoice = Commerce::IssueFinanceInvoice.call(order:, payment_record: payment).value.fetch(:document)
    first_refund = create_completed_refund(order:, payment:, amount_cents: 333)
    first_receipt = Commerce::IssueFinanceRefundReceipt.call(
      refund: first_refund,
      actor: @owner
    ).value.fetch(:document)
    Commerce::TransitionFinanceDocument.call(
      document: first_receipt,
      actor: @owner,
      action: "void",
      reason: "Void the first receipt without erasing allocation history.",
      request_id: SecureRandom.uuid
    )
    second_refund = create_completed_refund(order:, payment:, amount_cents: 668)
    second_receipt = Commerce::IssueFinanceRefundReceipt.call(
      refund: second_refund,
      actor: @owner
    ).value.fetch(:document)

    assert_equal invoice.tax_amount_cents,
      first_receipt.tax_amount_cents + second_receipt.tax_amount_cents
    assert_equal 2,
      second_receipt.content_snapshot.dig("allocation", "allocation_sequence")
  end

  test "payment completion issues one invoice before asynchronous side effects" do
    order, payment = create_paid_order(gross_cents: 1_500)

    first = Commerce::CompleteOrderPayment.call(order:)
    replay = Commerce::CompleteOrderPayment.call(order: order.reload)

    assert_predicate first, :success?, first.error
    assert_predicate replay, :success?, replay.error
    invoice = Commerce::FinanceDocument.invoice.issued.find_by!(order:)
    assert_equal payment.provider, invoice.channel
    assert_equal 1, Commerce::FinanceDocument.invoice.where(order:).count
  end

  test "summary keeps monetary totals separated by currency" do
    cny_order, cny_payment = create_paid_order(gross_cents: 1_001)
    usd_order, usd_payment = create_paid_order(gross_cents: 2_500, currency: "USD")
    Commerce::IssueFinanceInvoice.call(order: cny_order, payment_record: cny_payment)
    Commerce::IssueFinanceInvoice.call(order: usd_order, payment_record: usd_payment)

    summary = Commerce::FinanceDocumentQuery.new.summary
    totals = summary.fetch(:totals_by_currency).index_by { |total| total.fetch(:currency) }

    assert_equal 1_001, totals.fetch("CNY").fetch(:gross_cents)
    assert_equal 2_500, totals.fetch("USD").fetch(:gross_cents)
    assert_equal(
      Commerce::FinanceDocument.where(currency: "CNY").sum(:tax_amount_cents),
      totals.fetch("CNY").fetch(:tax_cents)
    )
    assert_equal(
      Commerce::FinanceDocument.where(currency: "USD").sum(:tax_amount_cents),
      totals.fetch("USD").fetch(:tax_cents)
    )
  end

  test "refund processing issues one receipt and replay does not allocate twice" do
    order, payment = create_paid_order(gross_cents: 1_001)
    invoice = Commerce::IssueFinanceInvoice.call(order:, payment_record: payment).value.fetch(:document)

    first = Commerce::ProcessRefund.call(
      order:,
      payment_record: payment,
      amount_cents: 400,
      reason: "Approved partial refund for unavailable item.",
      approved_by: @owner
    )
    assert_predicate first, :success?, first.error
    refund = first.value
    receipt = Commerce::FinanceDocument.refund_receipt.issued.find_by!(refund:)

    replay = Commerce::ProcessRefund.call(
      order: order.reload,
      payment_record: payment.reload,
      amount_cents: 400,
      reason: "Approved partial refund for unavailable item.",
      approved_by: @owner,
      existing_refund: refund
    )

    assert_predicate replay, :success?, replay.error
    assert_equal 1, Commerce::FinanceDocument.refund_receipt.where(refund:).count
    assert_equal 400, receipt.net_amount_cents + receipt.tax_amount_cents
    assert_operator receipt.tax_amount_cents, :<=, invoice.tax_amount_cents
  end

  test "refund receipt audit failure rolls back refund completion and document mutation" do
    order, payment = create_paid_order(gross_cents: 1_000)
    Commerce::IssueFinanceInvoice.call(order:, payment_record: payment)
    original = Administration::AuditLogger.method(:call)
    Administration::AuditLogger.define_singleton_method(:call) do |**attributes|
      if attributes[:action] == "commerce.finance_refund_receipt_issued"
        audit_log = AuditLog.new
        audit_log.errors.add(:base, "simulated immutable audit failure")
        raise ActiveRecord::RecordInvalid, audit_log
      end

      original.call(**attributes)
    end

    result = Commerce::ProcessRefund.call(
      order:,
      payment_record: payment,
      amount_cents: 500,
      reason: "Approved partial refund with audit rollback test.",
      approved_by: @owner
    )

    assert_predicate result, :failure?
    refund = Commerce::Refund.order(:id).last
    assert_not refund.completed?
    assert refund.restoration_failed?
    assert_equal 0, Commerce::FinanceDocument.refund_receipt.where(store_refund_id: refund.id).count
    assert_equal "paid", order.reload.status
  ensure
    Administration::AuditLogger.define_singleton_method(:call, original) if original
  end

  private

  def create_paid_order(gross_cents:, currency: "CNY")
    suffix = SecureRandom.hex(6)
    product = Commerce::Product.create!(
      public_id: "prod_fin_#{suffix}",
      name: "Finance test item",
      slug: "finance-test-item-#{suffix}",
      product_type: "digital",
      status: "active",
      price_cents: gross_cents,
      currency:,
      minimum_quantity: 1
    )
    order = Commerce::Order.create!(
      public_id: "ord_fin_#{suffix}",
      order_number: "FIN#{suffix.upcase}",
      user: @customer,
      status: "paid",
      subtotal_cents: gross_cents,
      total_cents: gross_cents,
      currency:,
      shipping_address: {}
    )
    Commerce::OrderItem.create!(
      order:,
      product:,
      product_name: "Finance test item",
      quantity: 1,
      unit_price_cents: gross_cents,
      total_cents: gross_cents
    )
    payment = Payments::Record.create!(
      order:,
      provider: "fake",
      status: "succeeded",
      amount_cents: gross_cents,
      currency:,
      provider_payment_id: "finance_payment_#{suffix}"
    )
    [ order, payment ]
  end

  def create_completed_refund(order:, payment:, amount_cents:)
    Commerce::Refund.create!(
      order:,
      payment_record: payment,
      status: "completed",
      restoration_status: "completed",
      amount_cents:,
      requested_by: @customer,
      approved_by: @owner,
      provider_confirmed_at: Time.current,
      restoration_completed_at: Time.current,
      provider_refund_id: "finance_refund_#{SecureRandom.hex(8)}",
      provider_status: "succeeded"
    )
  end
end
