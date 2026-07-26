# frozen_string_literal: true

require "test_helper"

class DeveloperModeAutoLoginTest < ActionDispatch::IntegrationTest
  test "configured user is signed in for a browser request" do
    owner = create_user(
      username: "developer_owner",
      account_type: "owner"
    )

    with_developer_mode_auto_login(owner.username.upcase) do
      assert_difference("Session.where(user: owner).count", 1) do
        get admin_root_path
      end

      assert_response :success
      assert cookies[:session_token].present?
      assert_predicate Session.where(user: owner).order(:id).last, :developer_mode?
    end
  end

  test "sessions issued in developer mode are revoked after the mode is disabled" do
    owner = create_user(
      username: "developer_session_owner",
      account_type: "owner"
    )
    session_record = nil

    with_developer_mode_auto_login(owner.username) do
      get admin_root_path
      assert_response :success
      session_record = Session.where(user: owner).order(:id).last
      assert_predicate session_record, :developer_mode?
    end

    get admin_root_path

    assert_redirected_to identity_sign_in_path
    assert_predicate session_record.reload, :revoked?
    assert cookies[:session_token].blank?
  end

  test "numeric identifier resolves a user id" do
    owner = create_user(account_type: "owner")

    with_developer_mode_auto_login(owner.id) do
      get admin_root_path

      assert_response :success
      assert_equal owner.id, Session.active.order(:id).last.user_id
    end
  end

  test "missing or ineligible configured user does not create a session" do
    banned = create_user(status: "banned")

    [ "missing-user", banned.username ].each do |identifier|
      with_developer_mode_auto_login(identifier) do
        assert_no_difference("Session.count") do
          get admin_root_path
        end

        assert_redirected_to identity_sign_in_path
      end
    end
  end

  test "non html endpoints do not receive an automatic browser session" do
    owner = create_user(account_type: "owner")

    with_developer_mode_auto_login(owner.username) do
      assert_no_difference("Session.where(user: owner).count") do
        get health_live_path, as: :json
      end

      assert_response :ok
      assert_nil cookies[:session_token]
    end
  end

  test "health probes never create automatic sessions even without a json accept header" do
    owner = create_user(account_type: "owner")

    with_developer_mode_auto_login(owner.username) do
      assert_no_difference("Session.where(user: owner).count") do
        get health_live_path
      end

      assert_response :ok
      assert_nil cookies[:session_token]
    end
  end

  test "automatic login does not grant admin permissions" do
    member = create_user(account_type: "member")

    with_developer_mode_auto_login(member.username) do
      get admin_root_path

      assert_redirected_to root_path
      assert_equal I18n.t("mcweb.flash.admin_access_denied"), flash[:alert]
    end
  end

  private

  def with_developer_mode_auto_login(identifier)
    settings = Mcweb::DeveloperMode.parse(
      config: {
        developer_mode: {
          enabled: true,
          auto_login_user: identifier
        }
      },
      environment: {}
    )
    previous_settings = Mcweb::DeveloperMode.instance_variable_get(:@settings)
    Mcweb::DeveloperMode.instance_variable_set(:@settings, settings)
    yield
  ensure
    Mcweb::DeveloperMode.instance_variable_set(:@settings, previous_settings)
  end
end
