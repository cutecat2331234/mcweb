# frozen_string_literal: true

require "test_helper"

module Identity
  class UpdateProfileTest < ActiveSupport::TestCase
    setup do
      @user = create_user(display_name: "Original name", locale: "zh-CN")
    end

    test "normalizes self-service fields and audits only fields that actually changed" do
      result = UpdateProfile.call(
        actor: @user,
        user: @user,
        attributes: { display_name: "  New 显示名  ", locale: "EN_us" },
        ip_address: "127.0.0.2",
        user_agent: "Profile test"
      )

      assert result.success?
      assert result.value.fetch(:changed)
      @user.reload
      assert_equal "New 显示名", @user.display_name
      assert_equal "en", @user.locale

      audit = AuditLog.find_by!(action: "identity.user.profile_updated", resource_id: @user.id)
      assert_equal %w[display_name locale], audit.metadata.fetch("changed_fields")
      assert_equal "127.0.0.2", audit.ip_address
      assert_equal "Profile test", audit.user_agent
    end

    test "turns a blank display name into nil without changing unrelated fields" do
      result = UpdateProfile.call(
        actor: @user,
        user: @user,
        attributes: { display_name: "   " }
      )

      assert result.success?
      assert_nil @user.reload.display_name
      audit = AuditLog.find_by!(action: "identity.user.profile_updated", resource_id: @user.id)
      assert_equal [ "display_name" ], audit.metadata.fetch("changed_fields")
    end

    test "a no-op does not create an audit event" do
      assert_no_difference -> { AuditLog.where(action: "identity.user.profile_updated").count } do
        result = UpdateProfile.call(
          actor: @user,
          user: @user,
          attributes: { display_name: " Original name ", locale: "zh-CN" }
        )

        assert result.success?
        refute result.value.fetch(:changed)
      end
    end

    test "rejects control characters and overlong display names" do
      [ "unsafe\u0007name", "x" * 65 ].each do |display_name|
        result = UpdateProfile.call(
          actor: @user,
          user: @user,
          attributes: { display_name: display_name }
        )

        assert result.failure?
        assert_equal "validation_failed", result.code
        assert result.errors.key?(:display_name)
        assert_equal "Original name", @user.reload.display_name
      end
    end

    test "rejects an unsupported locale without partially saving another field" do
      result = UpdateProfile.call(
        actor: @user,
        user: @user,
        attributes: { display_name: "Must not persist", locale: "unsupported" }
      )

      assert result.failure?
      assert_equal "validation_failed", result.code
      assert result.errors.key?(:locale)
      @user.reload
      assert_equal "Original name", @user.display_name
      assert_equal "zh-CN", @user.locale
      refute AuditLog.exists?(action: "identity.user.profile_updated", resource_id: @user.id)
    end
  end
end
