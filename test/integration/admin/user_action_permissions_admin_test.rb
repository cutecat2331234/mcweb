# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class UserActionPermissionsAdminTest < ActionDispatch::IntegrationTest
    setup do
      @actor = create_user(account_type: "staff")
      @target = create_user
      @badge = Community::Badge.create!(
        name: "Permission badge #{SecureRandom.hex(4)}",
        slug: "permission-badge-#{SecureRandom.hex(4)}",
        grant_rule: "manual"
      )

      grant_permission(@actor, "admin.access")
      grant_admin_module(@actor, "system")
      grant_admin_module(@actor, "forum")
      grant_admin_module(@actor, "store")
      sign_in_as(@actor)
    end

    test "admin access alone cannot mutate domain-specific user state" do
      assert_no_difference -> { Community::UserBadge.where(user: @target).count } do
        post grant_badge_admin_user_path(@target), params: { badge_slug: @badge.slug }
      end
      assert_redirected_to root_path

      assert_no_difference -> { Community::UserWarning.where(user: @target).count } do
        post warn_admin_user_path(@target), params: { reason: "warning", points: 1 }
      end
      assert_redirected_to root_path

      assert_no_difference -> { Community::StaffNote.where(user: @target).count } do
        post staff_note_admin_user_path(@target), params: { body: "private note" }
      end
      assert_redirected_to root_path

      assert_no_difference -> { Community::UserSilence.where(user: @target).count } do
        post silence_admin_user_path(@target), params: { reason: "silence", days: 1 }
      end
      assert_redirected_to root_path

      assert_no_changes -> { @target.reload.forum_trust_level_override } do
        post set_trust_level_admin_user_path(@target), params: { forum_trust_level_override: "2" }
      end
      assert_redirected_to root_path

      assert_no_changes -> { @target.reload.store_credit_cents } do
        post adjust_store_credit_admin_user_path(@target), params: { amount_cents: 500, note: "credit" }
      end
      assert_redirected_to root_path

      post authorize_store_credit_adjustment_admin_user_path(@target),
           params: { amount_cents: 500, note: "credit", request_id: SecureRandom.uuid },
           as: :json
      assert_redirected_to root_path
    end

    test "dedicated permissions and modules authorize each user action" do
      %w[
        forum.badges.manage
        forum.users.warn
        forum.users.mute
        forum.users.trust.manage
        store.credit.adjust
      ].each { |key| grant_permission(@actor, key) }

      assert_difference -> { Community::UserBadge.where(user: @target).count }, 1 do
        post grant_badge_admin_user_path(@target), params: { badge_slug: @badge.slug }
      end
      assert_redirected_to admin_user_path(@target)

      assert_difference -> { Community::UserBadge.where(user: @target).count }, -1 do
        post revoke_badge_admin_user_path(@target), params: { badge_slug: @badge.slug }
      end
      assert_redirected_to admin_user_path(@target)

      assert_difference -> { Community::UserWarning.where(user: @target).count }, 1 do
        post warn_admin_user_path(@target), params: { reason: "warning", points: 1 }
      end
      assert_redirected_to admin_user_path(@target)

      assert_difference -> { Community::StaffNote.where(user: @target).count }, 1 do
        post staff_note_admin_user_path(@target), params: { body: "private note" }
      end
      assert_redirected_to admin_user_path(@target)

      assert_difference -> { Community::UserSilence.where(user: @target).count }, 1 do
        post silence_admin_user_path(@target), params: { reason: "silence", days: 1 }
      end
      assert_redirected_to admin_user_path(@target)

      assert_difference -> { Community::UserSilence.where(user: @target).count }, -1 do
        post unsilence_admin_user_path(@target)
      end
      assert_redirected_to admin_user_path(@target)

      post set_trust_level_admin_user_path(@target), params: { forum_trust_level_override: "2" }
      assert_redirected_to admin_user_path(@target)
      assert_equal 2, @target.reload.forum_trust_level_override

      request_id = SecureRandom.uuid
      post authorize_store_credit_adjustment_admin_user_path(@target),
           params: { amount_cents: 500, note: "credit", request_id: request_id },
           as: :json
      assert_response :success
      assert_equal "no-store", response.headers["Cache-Control"]
      authorization = JSON.parse(response.body)

      assert_difference -> {
        AuditLog.where(
          action: "commerce.store_credit_adjusted",
          resource_type: "User",
          resource_id: @target.id
        ).count
      }, 1 do
        post adjust_store_credit_admin_user_path(@target),
             params: {
               amount_cents: 500,
               note: "credit",
               request_id: request_id,
               authorization_token: authorization.fetch("token"),
               confirmation: authorization.fetch("confirmation")
             },
             headers: { "HTTP_USER_AGENT" => "StoreCreditRequestTest" },
             as: :json
      end
      assert_response :success
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_equal false, JSON.parse(response.body).fetch("idempotent")
      assert_equal 500, @target.reload.store_credit_cents

      audit_log = AuditLog.where(
        action: "commerce.store_credit_adjusted",
        resource_type: "User",
        resource_id: @target.id
      ).order(:id).last
      assert_equal "StoreCreditRequestTest", audit_log.user_agent
      assert_equal 500, audit_log.after_state.fetch("store_credit_cents")
    end

    test "store credit endpoint requires the typed confirmation challenge" do
      grant_permission(@actor, "store.credit.adjust")
      authorization = issue_store_credit_adjustment(
        actor: @actor,
        user: @target,
        amount_cents: 500,
        note: "credit"
      )

      assert_no_changes -> { @target.reload.store_credit_cents } do
        assert_no_difference -> {
          AuditLog.where(action: "commerce.store_credit_adjusted", resource_id: @target.id).count
        } do
          post adjust_store_credit_admin_user_path(@target),
               params: {
                 amount_cents: 500,
                 note: "credit",
                 request_id: authorization[:request_id],
                 authorization_token: authorization[:token],
                 confirmation: "ADJUST WRONG"
               },
               as: :json
        end
      end

      assert_response :unprocessable_entity
      assert_equal I18n.t("mcweb.services.errors.store_credit_confirmation_required"),
                   JSON.parse(response.body).fetch("error")
    end

    test "store-only staff can authorize and adjust credit without system module access" do
      grant_permission(@actor, "store.credit.adjust")
      @actor.admin_module_grants.where(module_key: %w[system forum]).delete_all
      request_id = SecureRandom.uuid

      post authorize_store_credit_adjustment_admin_user_path(@target),
           params: { amount_cents: 250, note: "Store support correction", request_id: request_id },
           as: :json
      assert_response :success
      authorization = JSON.parse(response.body)

      post adjust_store_credit_admin_user_path(@target),
           params: {
             amount_cents: 250,
             note: "Store support correction",
             request_id: request_id,
             authorization_token: authorization.fetch("token"),
             confirmation: authorization.fetch("confirmation")
           },
           as: :json

      assert_response :success
      assert_equal 250, @target.reload.store_credit_cents
    end

    test "user detail forms require their permission and domain module" do
      grant_permission(@actor, "system.settings.manage")
      %w[
        forum.badges.manage
        forum.users.warn
        forum.users.mute
        forum.users.trust.manage
        store.credit.adjust
      ].each { |key| grant_permission(@actor, key) }

      get admin_user_path(@target)

      assert_response :success
      props = inertia.props.deep_symbolize_keys
      assert props.fetch(:badgeForm)
      assert props.fetch(:warningForm)
      assert props.fetch(:staffNoteForm)
      assert props.fetch(:spamCleanForm)
      assert props.fetch(:silenceForm)
      assert props.fetch(:trustLevelForm)
      store_credit_form = props.fetch(:storeCreditForm)
      assert_equal authorize_store_credit_adjustment_admin_user_path(@target),
                   store_credit_form.fetch(:authorization_url)

      @actor.admin_module_grants.where(module_key: %w[forum store]).delete_all
      get admin_user_path(@target)

      assert_response :success
      props = inertia.props.deep_symbolize_keys
      assert_nil props.fetch(:badgeForm)
      assert_nil props.fetch(:warningForm)
      assert_nil props.fetch(:staffNoteForm)
      assert_nil props.fetch(:spamCleanForm)
      assert_nil props.fetch(:silenceForm)
      assert_nil props.fetch(:trustLevelForm)
      assert_nil props.fetch(:storeCreditForm)
    end
  end
end
