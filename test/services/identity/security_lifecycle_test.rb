# frozen_string_literal: true

require "test_helper"

module Identity
  class SecurityLifecycleTest < ActiveSupport::TestCase
    setup do
      @user = create_user
    end

    test "regenerating recovery codes revokes every old code and records no secret in audit" do
      @user.setup_totp!
      @user.update!(totp_enabled: true)
      old_codes = @user.recovery_codes.dup
      code = ROTP::TOTP.new(@user.totp_secret).now

      result = RegenerateRecoveryCodes.call(
        user: @user,
        password: "password123",
        code: code,
        ip_address: "127.0.0.1",
        user_agent: "Security lifecycle test"
      )

      assert result.success?
      replacement = result.value.fetch(:codes)
      assert_equal 10, replacement.size
      assert_empty replacement & old_codes
      assert_equal replacement, @user.reload.recovery_codes

      old_codes.each do |old_code|
        refute @user.consume_recovery_code!(old_code)
      end

      audit = AuditLog.find_by!(
        action: "identity.totp_recovery_codes_regenerated",
        resource_id: @user.id
      )
      serialized = [ audit.metadata, audit.before_state, audit.after_state ].to_json
      (old_codes + replacement).each { |secret| refute_includes serialized, secret }
    end

    test "regeneration rejects an invalid password without consuming or replacing codes" do
      @user.setup_totp!
      @user.update!(totp_enabled: true)
      original_codes = @user.recovery_codes.dup

      result = RegenerateRecoveryCodes.call(
        user: @user,
        password: "wrong-password",
        code: ROTP::TOTP.new(@user.totp_secret).now
      )

      assert result.failure?
      assert_equal "password_incorrect", result.code
      assert_equal original_codes, @user.reload.recovery_codes
      assert_empty AuditLog.where(action: "identity.totp_recovery_codes_regenerated", resource_id: @user.id)
    end

    test "changing email requires reauthentication and keeps the current address until confirmation" do
      current_session = create_test_session(@user).value.fetch(:session)
      other_session = create_test_session(@user).value.fetch(:session)

      result = ChangeEmail.call(
        user: @user,
        email: "replacement@example.com",
        password: "password123",
        current_session: current_session,
        ip_address: "127.0.0.1",
        user_agent: "Security lifecycle test"
      )

      assert result.success?
      refute_equal "replacement@example.com", @user.reload.email
      assert @user.email_verified?
      refute current_session.reload.revoked?
      refute other_session.reload.revoked?
      request = result.value.fetch(:email_change_request)
      assert_predicate request, :pending?
      assert_equal "replacement@example.com", request.requested_email

      audit = AuditLog.find_by!(action: "identity.email_change_requested", resource_id: request.id)
      refute_includes audit.to_json, "replacement@example.com"
      assert_equal "example.com", audit.metadata.fetch("replacement_domain")
    end

    test "email change does not consume a recovery code when the email is unavailable" do
      taken = create_user
      @user.setup_totp!
      @user.update!(totp_enabled: true)
      recovery_code = @user.recovery_codes.first

      result = ChangeEmail.call(
        user: @user,
        email: taken.email,
        password: "password123",
        code: recovery_code
      )

      assert result.failure?
      assert_equal "email_not_available", result.code
      assert_includes @user.reload.recovery_codes, recovery_code
    end

    test "account closure anonymizes profile revokes access and retains an immutable audit" do
      session_record = create_test_session(@user).value.fetch(:session)
      original_email = @user.email
      original_username = @user.username

      result = CloseAccount.call(
        user: @user,
        password: "password123",
        confirmation: "DELETE",
        reason: "No longer using the community",
        ip_address: "127.0.0.1",
        user_agent: "Security lifecycle test"
      )

      assert result.success?
      @user.reload
      assert @user.deleted?
      assert @user.deleted_at.present?
      refute_equal original_email, @user.email
      refute_equal original_username, @user.username
      assert_nil @user.display_name
      assert session_record.reload.revoked?

      audit = AuditLog.find_by!(action: "identity.account_closed", resource_id: @user.id)
      assert_equal "profile_anonymized_financial_and_governance_records_retained",
                   audit.metadata.fetch("policy")
      assert_equal "stable_anonymous_author", audit.metadata.fetch("closure_outcome")
      results = @user.account_closure_results
      assert_equal "completed", results.dig("identity.profile", "status")
      assert_equal "stable_anonymous_author",
                   results.dig("identity.authored_content", "details", "outcome")
      refute_includes audit.to_json, original_email
    end

    test "account closure replays its persisted module results without executing twice" do
      first = CloseAccount.call(
        user: @user,
        password: "password123",
        confirmation: "DELETE"
      )
      persisted = @user.reload.account_closure_results.deep_dup

      replay = CloseAccount.call(
        user: @user,
        password: "no-longer-required-for-idempotent-replay",
        confirmation: "DELETE"
      )

      assert_predicate first, :success?
      assert_predicate replay, :success?
      assert replay.value.fetch(:replayed)
      assert_equal persisted, replay.value.fetch(:closure_results)
      assert_equal 1, AuditLog.where(action: "identity.account_closed", resource_id: @user.id).count
    end

    test "the last active owner cannot close their account" do
      User
        .where(account_type: :owner, status: :active)
        .where.not(id: @user.id)
        .update_all(account_type: :admin)
      @user.update!(account_type: :owner)

      assert_equal [ @user.id ], User.where(
        account_type: :owner,
        status: :active
      ).pluck(:id)

      result = CloseAccount.call(
        user: @user,
        password: "password123",
        confirmation: "DELETE"
      )

      assert result.failure?
      assert_equal "last_owner_account_cannot_close", result.code
      assert @user.reload.active?
    end

    test "an active successor owner permits account closure" do
      @user.update!(account_type: :owner)
      successor = create_user(account_type: :owner)

      result = CloseAccount.call(
        user: @user,
        password: "password123",
        confirmation: "DELETE"
      )

      assert result.success?
      assert @user.reload.deleted?
      assert successor.reload.active?
      assert successor.account_owner?
    end

    test "account closure can delete eligible authored content with a stable result" do
      category = Community::Category.create!(
        name: "Closure category #{SecureRandom.hex(4)}",
        slug: "closure-category-#{SecureRandom.hex(4)}"
      )
      section = Community::Section.create!(
        category:,
        name: "Closure section",
        slug: "closure-section-#{SecureRandom.hex(4)}",
        position: 0
      )
      topic = Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section:,
        user: @user,
        title: "Delete my authored content",
        status: :published,
        last_posted_at: Time.current,
        last_post_user: @user
      )
      post = Community::Post.create!(
        topic:,
        user: @user,
        floor_number: 1,
        body: "Personal authored post",
        status: :published
      )

      result = CloseAccount.call(
        user: @user,
        password: "password123",
        confirmation: "DELETE",
        closure_mode: "delete_content"
      )

      assert result.success?
      assert_equal "authored_content_deleted", @user.reload.account_closure_outcome
      assert_equal 1,
                   @user.account_closure_results
                     .dig("identity.authored_content", "details", "deleted_records", "topics")
      assert_equal 1,
                   @user.account_closure_results
                     .dig("identity.authored_content", "details", "deleted_records", "posts")
      assert_equal I18n.t("mcweb.identity.deleted_content_title"),
                   Community::Topic.with_discarded.find(topic.id).title
      assert_equal I18n.t("mcweb.identity.deleted_content_body"),
                   Community::Post.with_discarded.find(post.id).body
    end

    test "active legal hold overrides requested content deletion" do
      actor = create_user
      DataGovernance::PlaceRetentionHold.call(
        target: @user,
        actor:,
        reason: "Preserve content for an unresolved dispute."
      )

      result = CloseAccount.call(
        user: @user,
        password: "password123",
        confirmation: "DELETE",
        closure_mode: "delete_content"
      )

      assert result.success?
      assert_equal "legally_retained", @user.reload.account_closure_outcome
      audit = AuditLog.find_by!(action: "identity.account_closed", resource_id: @user.id)
      assert_equal "legally_retained", audit.metadata.fetch("closure_outcome")
    end

    test "verified email and password can reset lost totp and revoke every session" do
      @user.setup_totp!
      @user.update!(totp_enabled: true)
      session_record = create_test_session(@user).value.fetch(:session)
      captured = nil

      MailDeliveryJob.stub(:perform_later, ->(*args, **kwargs) { captured = [ args, kwargs ] }) do
        result = RecoverTotp.call(
          email: @user.email,
          ip_address: "127.0.0.1",
          user_agent: "Security lifecycle test"
        )
        assert result.success?
      end

      token = captured.last.fetch(:args).last
      result = RecoverTotp.call(
        token: token,
        password: "password123",
        ip_address: "127.0.0.1",
        user_agent: "Security lifecycle test"
      )

      assert result.success?
      @user.reload
      refute @user.totp_enabled?
      assert_nil @user.totp_secret
      assert_empty Array(@user.recovery_codes)
      assert_nil @user.totp_recovery_token_digest
      assert session_record.reload.revoked?
      assert AuditLog.exists?(action: "identity.totp_recovered", resource_id: @user.id)
    end

    test "expired totp recovery token cannot change account state" do
      @user.setup_totp!
      token = SecureRandom.urlsafe_base64(32)
      @user.update!(
        totp_enabled: true,
        totp_recovery_token_digest: Digest::SHA256.hexdigest(token),
        totp_recovery_sent_at: 31.minutes.ago
      )

      result = RecoverTotp.call(token: token, password: "password123", ip_address: "127.0.0.1")

      assert result.failure?
      assert_equal "invalid_or_expired_totp_recovery_token", result.code
      assert @user.reload.totp_enabled?
    end
  end
end
