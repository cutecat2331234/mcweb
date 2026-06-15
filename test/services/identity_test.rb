# frozen_string_literal: true

require "test_helper"

class Identity::RegisterUserTest < ActiveSupport::TestCase
  test "registers a user with email verification token" do
    assert_enqueued_with(job: MailDeliveryJob) do
      result = Identity::RegisterUser.call(
        email: "new@example.com",
        username: "newuser",
        password: "password123"
      )

      assert result.success?
      user = result.value[:user]
      assert_equal "new@example.com", user.email
      assert_not user.email_verified?
      assert result.value[:verification_token].present?
    end
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
end

class Identity::PermissionCheckerTest < ActiveSupport::TestCase
  test "allows user with permission" do
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
end

class Identity::ResetPasswordTest < ActiveSupport::TestCase
  test "sends reset email for existing user" do
    user = create_user(email: "reset@example.com", username: "resetuser")

    assert_enqueued_with(job: MailDeliveryJob) do
      result = Identity::ResetPassword.call(email: "reset@example.com")
      assert result.success?
      assert result.value[:reset_token].present?
    end

    user.reload
    assert user.password_reset_token_digest.present?
  end
end

class Admin::MinecraftServersControllerTest < ActionDispatch::IntegrationTest
  test "lists servers without host field error" do
    admin = create_user(email: "mcadmin@example.com", username: "mcadmin")
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
