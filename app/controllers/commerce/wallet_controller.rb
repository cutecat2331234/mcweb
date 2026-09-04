# frozen_string_literal: true

module Commerce
  class WalletController < ApplicationController
    include PrivateNoStoreResponse
    include StoreCreditLedgerSerialization

    before_action :require_login

    def show
      result = Commerce::StoreCreditLedgerPage.call(user: current_user, cursor: params[:cursor])
      return redirect_to store_wallet_path, alert: service_error_message(result) unless result.success?

      transactions = result.value.fetch(:transactions)
      pagination = result.value.fetch(:pagination)

      render inertia: "Commerce/Wallet/Show", props: {
        balanceCents: current_user.store_credit_cents.to_i,
        balanceLabel: format_money(current_user.store_credit_cents.to_i, "CNY"),
        memberships: Commerce::SerializeUserMemberships.for_user(current_user),
        transactions: transactions.map do |transaction|
          serialize_store_credit_ledger_entry(
            transaction,
            order_url: transaction.order ? store_order_path(transaction.order) : nil
          )
        end,
        pagination: {
          has_more: pagination.fetch(:has_more),
          next_url: pagination[:next_cursor] ? store_wallet_path(cursor: pagination[:next_cursor]) : nil
        }
      }
    end
  end
end
