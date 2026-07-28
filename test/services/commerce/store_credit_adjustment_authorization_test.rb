# frozen_string_literal: true

require "test_helper"

module Commerce
  class StoreCreditAdjustmentAuthorizationTest < ActiveSupport::TestCase
    setup do
      @actor = create_user(account_type: "staff")
      @target = create_user
      grant_permission(@actor, "store.credit.adjust")
      @request_id = SecureRandom.uuid
      @note = "Support ticket MC-42"
    end

    test "authorization is short lived and bound to actor target balance amount request and note" do
      authorization = issue_store_credit_adjustment(
        actor: @actor,
        user: @target,
        amount_cents: 500,
        request_id: @request_id.upcase,
        note: @note
      )

      assert_equal @request_id, authorization[:request_id]
      assert StoreCreditAdjustmentAuthorization.valid?(
        authorization[:token],
        actor: @actor,
        user: @target,
        current_balance_cents: 0,
        amount_cents: 500,
        request_id: @request_id,
        note: @note
      )

      other_actor = create_user(account_type: "staff")
      grant_permission(other_actor, "store.credit.adjust")
      other_target = create_user
      [
        {
          actor: other_actor, user: @target, current_balance_cents: 0,
          amount_cents: 500, request_id: @request_id, note: @note
        },
        {
          actor: @actor, user: other_target, current_balance_cents: 0,
          amount_cents: 500, request_id: @request_id, note: @note
        },
        {
          actor: @actor, user: @target, current_balance_cents: 1,
          amount_cents: 500, request_id: @request_id, note: @note
        },
        {
          actor: @actor, user: @target, current_balance_cents: 0,
          amount_cents: 501, request_id: @request_id, note: @note
        },
        {
          actor: @actor, user: @target, current_balance_cents: 0,
          amount_cents: 500, request_id: SecureRandom.uuid, note: @note
        },
        {
          actor: @actor, user: @target, current_balance_cents: 0,
          amount_cents: 500, request_id: @request_id, note: "Different reason"
        }
      ].each do |attributes|
        refute StoreCreditAdjustmentAuthorization.valid?(
          authorization[:token],
          **attributes
        )
      end

      travel StoreCreditAdjustmentAuthorization::EXPIRES_IN + 1.second do
        refute StoreCreditAdjustmentAuthorization.valid?(
          authorization[:token],
          actor: @actor,
          user: @target,
          current_balance_cents: 0,
          amount_cents: 500,
          request_id: @request_id,
          note: @note
        )
      end
    end

    test "successful request is single effect and identical retry returns the original result" do
      authorization = issue_store_credit_adjustment(
        actor: @actor,
        user: @target,
        amount_cents: 500,
        request_id: @request_id,
        note: @note
      )
      arguments = {
        actor: @actor,
        user: @target,
        amount_cents: 500,
        request_id: @request_id,
        authorization_token: authorization[:token],
        confirmation: authorization[:confirmation],
        note: @note
      }

      first = nil
      assert_difference -> { StoreCreditTransaction.where(request_id: @request_id).count }, 1 do
        assert_difference -> { AuditLog.by_action("commerce.store_credit_adjusted").count }, 1 do
          first = AdjustStoreCredit.call(**arguments)
        end
      end
      assert_predicate first, :success?
      refute first.value[:idempotent]
      assert_equal 500, first.value[:balance_cents]

      second = nil
      assert_no_difference -> { StoreCreditTransaction.where(request_id: @request_id).count } do
        assert_no_difference -> { AuditLog.by_action("commerce.store_credit_adjusted").count } do
          second = AdjustStoreCredit.call(**arguments)
        end
      end
      assert_predicate second, :success?
      assert second.value[:idempotent]
      assert_equal first.value[:transaction].id, second.value[:transaction].id
      assert_equal first.value[:balance_cents], second.value[:balance_cents]
      assert_equal 500, @target.reload.store_credit_cents

      transaction = first.value[:transaction]
      assert_equal @request_id, transaction.request_id
      assert_equal 0, transaction.balance_before_cents
      assert_equal 500, transaction.balance_after_cents
      assert_equal 64, transaction.request_fingerprint.length
      assert_equal 64, transaction.authorization_digest.length
    end

    test "same request id with different payload is rejected" do
      authorization = issue_store_credit_adjustment(
        actor: @actor,
        user: @target,
        amount_cents: 500,
        request_id: @request_id,
        note: @note
      )
      first = AdjustStoreCredit.call(
        actor: @actor,
        user: @target,
        amount_cents: 500,
        request_id: @request_id,
        authorization_token: authorization[:token],
        confirmation: authorization[:confirmation],
        note: @note
      )
      assert_predicate first, :success?

      assert_no_changes -> { @target.reload.store_credit_cents } do
        conflict = AdjustStoreCredit.call(
          actor: @actor,
          user: @target,
          amount_cents: 600,
          request_id: @request_id,
          authorization_token: authorization[:token],
          confirmation: authorization[:confirmation],
          note: @note
        )
        assert_predicate conflict, :failure?
        assert_equal I18n.t("mcweb.services.errors.store_credit_request_id_reused"),
                     conflict.error
      end
    end

    test "balance changes and token reuse with another request fail closed" do
      authorization = issue_store_credit_adjustment(
        actor: @actor,
        user: @target,
        amount_cents: 500,
        request_id: @request_id,
        note: @note
      )
      @target.update!(store_credit_cents: 100)

      assert_no_changes -> { @target.reload.store_credit_cents } do
        stale = AdjustStoreCredit.call(
          actor: @actor,
          user: @target,
          amount_cents: 500,
          request_id: @request_id,
          authorization_token: authorization[:token],
          confirmation: authorization[:confirmation],
          note: @note
        )
        assert_predicate stale, :failure?
        assert_equal I18n.t("mcweb.services.errors.store_credit_authorization_invalid"),
                     stale.error
      end

      @target.update!(store_credit_cents: 0)
      another_request_id = SecureRandom.uuid
      assert_no_changes -> { @target.reload.store_credit_cents } do
        rebound = AdjustStoreCredit.call(
          actor: @actor,
          user: @target,
          amount_cents: 500,
          request_id: another_request_id,
          authorization_token: authorization[:token],
          confirmation: StoreCreditAdjustmentAuthorization.confirmation_for(
            user: @target,
            amount_cents: 500,
            request_id: another_request_id
          ),
          note: @note
        )
        assert_predicate rebound, :failure?
        assert_equal I18n.t("mcweb.services.errors.store_credit_authorization_invalid"),
                     rebound.error
      end
    end

    test "authorization requires a dedicated permission valid uuid amount and business reason" do
      unauthorized = create_user(account_type: "staff")

      result = StoreCreditAdjustmentAuthorization.issue(
        actor: unauthorized,
        user: @target,
        amount_cents: 500,
        request_id: @request_id,
        note: @note
      )
      assert_predicate result, :failure?
      assert_equal I18n.t("mcweb.services.errors.store_credit_unauthorized"), result.error

      {
        "not-a-uuid" => "store_credit_request_id_invalid",
        nil => "store_credit_request_id_invalid"
      }.each do |request_id, error_key|
        result = StoreCreditAdjustmentAuthorization.issue(
          actor: @actor,
          user: @target,
          amount_cents: 500,
          request_id: request_id,
          note: @note
        )
        assert_predicate result, :failure?
        assert_equal I18n.t("mcweb.services.errors.#{error_key}"), result.error
      end

      result = StoreCreditAdjustmentAuthorization.issue(
        actor: @actor,
        user: @target,
        amount_cents: "five hundred",
        request_id: @request_id,
        note: @note
      )
      assert_predicate result, :failure?
      assert_equal I18n.t("mcweb.services.errors.store_credit_amount_invalid"), result.error

      result = StoreCreditAdjustmentAuthorization.issue(
        actor: @actor,
        user: @target,
        amount_cents: StoreCreditAdjustmentAuthorization::MAX_ABSOLUTE_AMOUNT_CENTS + 1,
        request_id: @request_id,
        note: @note
      )
      assert_predicate result, :failure?
      assert_equal I18n.t("mcweb.services.errors.store_credit_amount_out_of_range"),
                   result.error

      result = StoreCreditAdjustmentAuthorization.issue(
        actor: @actor,
        user: @target,
        amount_cents: 500,
        request_id: @request_id,
        note: " "
      )
      assert_predicate result, :failure?
      assert_equal I18n.t("mcweb.services.errors.store_credit_note_required"), result.error

      @target.update!(
        store_credit_cents: StoreCreditAdjustmentAuthorization::MAX_BALANCE_CENTS - 50
      )
      result = StoreCreditAdjustmentAuthorization.issue(
        actor: @actor,
        user: @target,
        amount_cents: 100,
        request_id: @request_id,
        note: @note
      )
      assert_predicate result, :failure?
      assert_equal I18n.t("mcweb.services.errors.store_credit_balance_out_of_range"),
                   result.error
    end

    test "authorization token and typed confirmation are filtered from parameter logs" do
      filter = ActiveSupport::ParameterFilter.new(
        Rails.application.config.filter_parameters
      )
      filtered = filter.filter(
        "authorization_token" => "signed-secret",
        "confirmation" => "typed-secret",
        "request_id" => @request_id
      )

      assert_equal "[FILTERED]", filtered.fetch("authorization_token")
      assert_equal "[FILTERED]", filtered.fetch("confirmation")
      assert_equal @request_id, filtered.fetch("request_id")
    end
  end
end
