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

      post adjust_store_credit_admin_user_path(@target), params: { amount_cents: 500, note: "credit" }
      assert_redirected_to admin_user_path(@target)
      assert_equal 500, @target.reload.store_credit_cents
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
      assert props.fetch(:storeCreditForm)

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
