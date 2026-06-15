# frozen_string_literal: true

module Commerce
  class WalletController < ApplicationController
    before_action :require_login

    def show
      transactions = current_user.store_credit_transactions.includes(:order).recent.limit(50)

      render inertia: "Commerce/Wallet/Show", props: {
        balanceCents: current_user.store_credit_cents.to_i,
        balanceLabel: format_money(current_user.store_credit_cents.to_i, "CNY"),
        transactions: transactions.map do |tx|
          {
            amount_cents: tx.amount_cents,
            amount_label: format_money(tx.amount_cents.abs, "CNY"),
            credit: tx.amount_cents.positive?,
            note: tx.note,
            created_at: l(tx.created_at, format: :short),
            order_url: tx.order ? store_order_path(tx.order) : nil
          }
        end
      }
    end
  end
end
