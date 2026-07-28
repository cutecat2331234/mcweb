# frozen_string_literal: true

module Commerce
  class AdjustStoreCredit < ApplicationService
    def initialize(actor:, user:, amount_cents:, request_id: nil, authorization_token: nil,
                   confirmation: nil, note: nil, ip_address: nil, user_agent: nil)
      @actor = actor
      @user = user
      @amount_cents = StoreCreditAdjustmentAuthorization.normalize_amount(amount_cents)
      @request_id = StoreCreditAdjustmentAuthorization.normalize_request_id(request_id)
      @authorization_token = authorization_token.to_s
      @confirmation = confirmation.to_s.strip
      @note = StoreCreditAdjustmentAuthorization.normalize_note(note)
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return ServiceResult.failure(error: "store_credit_unauthorized") unless authorized?
      return ServiceResult.failure(error: "store_credit_amount_invalid") if @amount_cents.nil?
      return ServiceResult.failure(error: "store_credit_adjustment_zero") if @amount_cents.zero?
      if @amount_cents.abs > StoreCreditAdjustmentAuthorization::MAX_ABSOLUTE_AMOUNT_CENTS
        return ServiceResult.failure(error: "store_credit_amount_out_of_range")
      end
      return ServiceResult.failure(error: "store_credit_request_id_invalid") unless @request_id
      return ServiceResult.failure(error: "store_credit_note_required") if @note.blank?
      if @note.length > StoreCreditAdjustmentAuthorization::MAX_NOTE_LENGTH
        return ServiceResult.failure(error: "store_credit_note_too_long")
      end

      @request_fingerprint = StoreCreditAdjustmentAuthorization.request_fingerprint(
        actor: @actor,
        user: @user,
        amount_cents: @amount_cents,
        request_id: @request_id,
        note: @note
      )

      existing = Commerce::StoreCreditTransaction.find_by(request_id: @request_id)
      return idempotency_result(existing) if existing

      return ServiceResult.failure(error: "store_credit_authorization_invalid") if @authorization_token.blank?
      return ServiceResult.failure(error: "store_credit_confirmation_required") unless confirmation_valid?

      new_balance = nil
      transaction = nil

      Commerce::StoreCreditTransaction.transaction do
        @user.lock!
        existing = Commerce::StoreCreditTransaction.find_by(request_id: @request_id)
        return idempotency_result(existing) if existing

        previous_balance = @user.store_credit_cents.to_i
        unless StoreCreditAdjustmentAuthorization.valid?(
          @authorization_token,
          actor: @actor,
          user: @user,
          current_balance_cents: previous_balance,
          amount_cents: @amount_cents,
          request_id: @request_id,
          note: @note
        )
          return ServiceResult.failure(error: "store_credit_authorization_invalid")
        end

        new_balance = previous_balance + @amount_cents
        return ServiceResult.failure(error: "store_credit_negative_balance") if new_balance.negative?
        if new_balance > StoreCreditAdjustmentAuthorization::MAX_BALANCE_CENTS
          return ServiceResult.failure(error: "store_credit_balance_out_of_range")
        end

        reserved = previous_balance - @user.available_store_credit_cents
        if new_balance < reserved
          return ServiceResult.failure(error: "store_credit_below_reserved")
        end

        @user.update!(store_credit_cents: new_balance)
        transaction = Commerce::StoreCreditTransaction.create!(
          user: @user,
          actor: @actor,
          amount_cents: @amount_cents,
          note: @note,
          request_id: @request_id,
          request_fingerprint: @request_fingerprint,
          authorization_digest: StoreCreditAdjustmentAuthorization.authorization_digest(
            @authorization_token
          ),
          balance_before_cents: previous_balance,
          balance_after_cents: new_balance
        )
        Administration::AuditLogger.call(
          actor: @actor,
          action: "commerce.store_credit_adjusted",
          resource: @user,
          metadata: {
            amount_cents: @amount_cents,
            store_credit_transaction_id: transaction.id,
            confirmation_method: "signed_typed_challenge",
            request_id: @request_id
          },
          before_state: { store_credit_cents: previous_balance },
          after_state: { store_credit_cents: new_balance },
          ip_address: @ip_address,
          user_agent: @user_agent,
          reason: @note
        )
      end

      ServiceResult.success(
        balance_cents: new_balance,
        transaction: transaction,
        request_id: @request_id,
        idempotent: false
      )
    rescue ActiveRecord::RecordNotUnique
      existing = Commerce::StoreCreditTransaction.find_by(request_id: @request_id)
      return idempotency_result(existing) if existing

      ServiceResult.failure(error: "store_credit_authorization_invalid")
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def authorized?
      return false if @actor.id == @user.id

      @actor.permission?("store.credit.adjust")
    end

    def confirmation_valid?
      expected = StoreCreditAdjustmentAuthorization.confirmation_for(
        user: @user,
        amount_cents: @amount_cents,
        request_id: @request_id
      )
      return false unless @confirmation.bytesize == expected.bytesize

      ActiveSupport::SecurityUtils.secure_compare(@confirmation, expected)
    end

    def idempotency_result(existing)
      return ServiceResult.failure(error: "store_credit_request_id_reused") unless existing
      unless secure_match?(existing.request_fingerprint, @request_fingerprint)
        return ServiceResult.failure(error: "store_credit_request_id_reused")
      end

      ServiceResult.success(
        balance_cents: existing.balance_after_cents,
        transaction: existing,
        request_id: existing.request_id,
        idempotent: true
      )
    end

    def secure_match?(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(left, right)
    end
  end
end
