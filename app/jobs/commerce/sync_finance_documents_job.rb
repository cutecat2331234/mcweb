# frozen_string_literal: true

module Commerce
  class SyncFinanceDocumentsJob < ApplicationJob
    queue_as :maintenance

    ORDER_STATUSES = IssueFinanceInvoice::ELIGIBLE_ORDER_STATUSES

    def perform
      sync_invoices
      sync_refund_receipts
    end

    private

    def sync_invoices
      documented_order_ids = FinanceDocument.invoice.select(:store_order_id)
      Commerce::Order.where(status: ORDER_STATUSES)
        .where.not(id: documented_order_ids)
        .find_each do |order|
          IssueFinanceInvoice.call(order:)
        end
    end

    def sync_refund_receipts
      documented_refund_ids = FinanceDocument.refund_receipt.select(:store_refund_id)
      Commerce::Refund.completed
        .where.not(id: documented_refund_ids)
        .find_each do |refund|
          IssueFinanceRefundReceipt.call(refund:, actor: refund.approved_by || refund.requested_by)
        end
    end
  end
end
