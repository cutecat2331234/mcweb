# frozen_string_literal: true

module StoreCreditLedgerSerialization
  extend ActiveSupport::Concern

  private

  def serialize_store_credit_ledger_entry(transaction, order_url: nil, include_actor: false)
    {
      ledger_id: "SC-#{transaction.id}",
      amount_cents: transaction.amount_cents,
      amount_label: format_money(transaction.amount_cents.abs, "CNY"),
      credit: transaction.amount_cents.positive?,
      source_label: store_credit_source_label(transaction),
      note: transaction.note,
      balance_before_label: store_credit_balance_label(transaction.balance_before_cents),
      balance_after_label: store_credit_balance_label(transaction.balance_after_cents),
      order_number: transaction.order&.order_number,
      order_url: order_url,
      actor_name: include_actor ? transaction.actor&.username : nil,
      created_at: l(transaction.created_at, format: :short)
    }
  end

  def store_credit_source_label(transaction)
    key = if transaction.order
      transaction.amount_cents.positive? ? "order_refund" : "order_debit"
    elsif transaction.request_id.present?
      "admin_adjustment"
    elsif transaction.amount_cents.positive?
      "credit"
    else
      "debit"
    end

    t("mcweb.commerce.store_credit_ledger.sources.#{key}")
  end

  def store_credit_balance_label(amount_cents)
    return if amount_cents.nil?

    format_money(amount_cents, "CNY")
  end
end
