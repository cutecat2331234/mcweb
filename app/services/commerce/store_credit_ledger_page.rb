# frozen_string_literal: true

module Commerce
  class StoreCreditLedgerPage < ApplicationService
    PAGE_SIZE = 50
    CURSOR_PURPOSE = "commerce.store_credit_ledger.v1"

    def initialize(user:, cursor: nil)
      @user = user
      @cursor = cursor.to_s.presence
    end

    def call
      boundary = decode_cursor
      return ServiceResult.failure(error: "store_credit_cursor_invalid") if @cursor && boundary.nil?

      scope = Commerce::StoreCreditTransaction
        .where(user: @user)
        .includes(:order, :actor)
        .order(created_at: :desc, id: :desc)
      if boundary
        scope = scope.where(
          "(store_credit_transactions.created_at < :created_at OR " \
            "(store_credit_transactions.created_at = :created_at AND " \
            "store_credit_transactions.id < :id))",
          created_at: boundary.fetch(:created_at),
          id: boundary.fetch(:id)
        )
      end

      rows = scope.limit(PAGE_SIZE + 1).to_a
      has_more = rows.length > PAGE_SIZE
      rows = rows.first(PAGE_SIZE)

      ServiceResult.success(
        transactions: rows,
        pagination: {
          has_more: has_more,
          next_cursor: has_more ? encode_cursor(rows.last) : nil,
          page_size: PAGE_SIZE
        }
      )
    end

    private

    def decode_cursor
      return unless @cursor

      payload = verifier.verify(@cursor)
      return unless payload.is_a?(Hash)
      return unless payload["version"] == 1
      return unless payload["user_id"] == @user.id

      before_id = Integer(payload["before_id"], exception: false)
      before_created_at = Time.iso8601(payload["before_created_at"].to_s)
      return unless before_id&.positive?

      { id: before_id, created_at: before_created_at }
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, TypeError
      nil
    end

    def encode_cursor(transaction)
      verifier.generate(
        {
          "version" => 1,
          "user_id" => @user.id,
          "before_id" => transaction.id,
          "before_created_at" => transaction.created_at.iso8601(6)
        }
      )
    end

    def verifier
      Rails.application.message_verifier(CURSOR_PURPOSE)
    end
  end
end
