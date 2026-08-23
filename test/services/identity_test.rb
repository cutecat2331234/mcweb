# frozen_string_literal: true

require "test_helper"

class Identity::RegisterUserTest < ActiveSupport::TestCase
  test "registers a user with email verification token" do
    email = "new-#{SecureRandom.hex(4)}@example.com"
    username = "newuser#{SecureRandom.hex(4)}"
    result = Identity::RegisterUser.call(
      email: email,
      username: username,
      password: "password123",
      ip_address: "127.0.0.1"
    )

    assert result.success?
    user = result.value[:user]
    assert_equal email, user.email
    assert_not user.email_verified?
    assert result.value[:verification_token].present?
    assert Operations::DurableEnqueueIntent.exists?(
      handler_key: Identity::EmailVerificationDelivery::HANDLER_KEY,
      source_id: user.id
    )
  end

  test "rejects passwords shorter than six characters" do
    result = Identity::RegisterUser.call(
      email: "short-#{SecureRandom.hex(4)}@example.com",
      username: "shortpw#{SecureRandom.hex(4)}",
      password: "12345",
      ip_address: "127.0.0.1"
    )

    assert result.failure?
    assert result.errors[:password].present?
  end
end

class Identity::AuthenticateUserTest < ActiveSupport::TestCase
  test "authenticates valid credentials" do
    user = create_user(email: "auth@example.com", username: "authuser")
    result = Identity::AuthenticateUser.call(
      email: "auth@example.com",
      password: "password123",
      ip_address: "127.0.0.1",
      user_agent: "Test"
    )

    assert result.success?
    assert_equal user.id, result.value[:session].user_id
    assert result.value[:token].present?
  end

  test "rejects invalid password" do
    create_user(email: "bad@example.com", username: "baduser")
    result = Identity::AuthenticateUser.call(
      email: "bad@example.com",
      password: "wrong",
      ip_address: "127.0.0.1",
      user_agent: "Test"
    )

    assert result.failure?
  end

  test "rejects unverified email" do
    create_user(email: "unverified@example.com", username: "unverified", email_verified: false, email_verified_at: nil)
    result = Identity::AuthenticateUser.call(
      email: "unverified@example.com",
      password: "password123",
      ip_address: "127.0.0.1",
      user_agent: "Test"
    )

    assert result.failure?
    assert_equal I18n.t("mcweb.services.errors.invalid_email_or_password"), result.error
  end
end

class Identity::PermissionCheckerTest < ActiveSupport::TestCase
  test "allows user with role permission" do
    user = create_user
    grant_permission(user, "admin.access")
    result = Identity::PermissionChecker.call(user: user, permission_key: "admin.access")
    assert result.success?
    assert result.value[:allowed]
  end

  test "denies user without permission" do
    user = create_user
    result = Identity::PermissionChecker.call(user: user, permission_key: "admin.access")
    assert result.success?
    assert_not result.value[:allowed]
  end

  test "allows user with global identity group permission" do
    user = create_user
    group = create_permission_group(
      name: "Conversation members",
      permissions: [ "forum.conversations.create" ]
    )
    Community::GroupMembership.create!(user:, user_group: group)

    result = Identity::PermissionChecker.call(
      user: User.find(user.id),
      permission_key: "forum.conversations.create"
    )

    assert result.success?
    assert result.value[:allowed]
  end

  test "owner retains the owner permission invariant without a role row" do
    owner = create_user(account_type: "owner")

    result = Identity::PermissionChecker.call(
      user: owner,
      permission_key: "identity.groups.permissions.manage"
    )

    assert result.success?
    assert result.value[:allowed]
  end

  test "revoking role and group sources takes effect on the next check" do
    user = create_user
    permission_key = "identity.groups.members.assign"
    grant_permission(user, permission_key)
    group = create_permission_group(
      name: "Identity operators",
      permissions: [ permission_key ]
    )
    membership = Community::GroupMembership.create!(user:, user_group: group)

    assert Identity::PermissionChecker.call(
      user:,
      permission_key:
    ).value[:allowed]

    user.roles.each { |role| role.permissions.delete(Permission.find_by!(key: permission_key)) }
    membership.destroy!
    group.update!(permissions: [])

    result = Identity::PermissionChecker.call(
      user: User.find(user.id),
      permission_key:
    )

    assert result.success?
    assert_not result.value[:allowed]
  end

  private

  def create_permission_group(attributes)
    attributes = attributes.dup
    if Community::UserGroup.column_names.include?("key")
      attributes[:key] = "permission-checker-#{SecureRandom.hex(4)}"
    end
    Community::UserGroup.create!(attributes)
  end
end

class Identity::ResetPasswordTest < ActiveSupport::TestCase
  test "records durable reset email for existing user" do
    user = create_user(email: "reset@example.com", username: "resetuser")

    result = Identity::ResetPassword.call(email: "reset@example.com")
    assert result.success?
    assert result.value[:reset_token].present?

    user.reload
    assert user.password_reset_token_digest.present?
    assert user.password_reset_token.present?
    intent = Operations::DurableEnqueueIntent.find_by!(
      handler_key: Identity::SecurityRecoveryMailDelivery::HANDLER_KEY,
      source_id: user.id
    )
    assert_equal "password_reset", intent.arguments.fetch("purpose")
  end

  test "completion revokes sessions through the model lifecycle" do
    user = create_user(
      email: "reset-sessions@example.com",
      username: "resetsessions"
    )
    session = Session.create!(
      user:,
      token_digest: SecureRandom.hex(32),
      expires_at: 1.day.from_now
    )
    session.update_columns(
      created_at: 2.days.ago,
      updated_at: 2.days.ago
    )
    previous_updated_at = session.reload.updated_at
    totp_recovery_token = SecureRandom.urlsafe_base64(32)
    user.update!(
      totp_recovery_token: totp_recovery_token,
      totp_recovery_token_digest: Digest::SHA256.hexdigest(totp_recovery_token),
      totp_recovery_sent_at: Time.current
    )
    request = Identity::ResetPassword.call(email: user.email)

    result = Identity::ResetPassword.call(
      token: request.value.fetch(:reset_token),
      new_password: "newpassword456",
      ip_address: "203.0.113.21",
      user_agent: "Reset completion test"
    )

    assert_predicate result, :success?
    assert_predicate session.reload, :revoked?
    assert_operator session.updated_at, :>, previous_updated_at
    user.reload
    assert_nil user.password_reset_token
    assert_nil user.totp_recovery_token
    audit = AuditLog.find_by!(
      action: "identity.password_reset_completed",
      resource_id: user.id
    )
    assert_equal "203.0.113.21", audit.ip_address
    assert_equal "Reset completion test", audit.user_agent
    refute_includes audit.attributes.to_json, request.value.fetch(:reset_token)
    refute_includes audit.attributes.to_json, "newpassword456"
  end
end

class Identity::MailerTest < ActionMailer::TestCase
  test "verification email includes token link" do
    user = create_user(email: "mailer@example.com", username: "maileruser")
    token = "test-verification-token"

    email = Identity::Mailer.verification_email(user.id, token)

    assert_equal [ "mailer@example.com" ], email.to
    body = [ email.text_part&.body&.decoded, email.html_part&.body&.decoded, email.body.decoded ].compact.join
    assert_includes body, token
  end
end

class Admin::MinecraftServersControllerTest < ActionDispatch::IntegrationTest
  test "lists servers without host field error" do
    admin = create_user(email: "mcadmin@example.com", username: "mcadmin", account_type: "admin")
    grant_permission(admin, "admin.access")
    grant_permission(admin, "minecraft.servers.manage")
    sign_in_as(admin)

    Minecraft::Server.create!(
      public_id: "srv_list1",
      name: "Survival",
      address: "play.example.com",
      port: 25565
    )

    get admin_minecraft_servers_path
    assert_response :success
  end
end
