# frozen_string_literal: true

require "test_helper"

class DeveloperModePersonaSwitchTest < ActionDispatch::IntegrationTest
  test "route is hidden before authentication when Developer Mode is disabled" do
    with_developer_mode(enabled: false) do
      switch_persona("member")

      assert_response :not_found
    end
  end

  test "authorized operator can switch and a persona can switch back" do
    operator = create_user(account_type: "owner")

    with_developer_mode(enabled: true) do
      seed = Operations::DeveloperScenarioSeeder.call(
        scenario: "personas",
        actor: operator
      )
      assert_predicate seed, :success?
      sign_in_as(operator)

      switch_persona("member")
      assert_redirected_to Mcweb::Paths::APP_PREFIX

      member = User.find_by!(developer_mode_persona: "member")
      assert_equal member.id, authenticated_session.user_id

      switch_persona("owner")
      assert_redirected_to Mcweb::Paths::APP_PREFIX

      owner = User.find_by!(developer_mode_persona: "owner")
      assert_equal owner.id, authenticated_session.user_id
      assert_equal 2,
        AuditLog.by_action(
          "developer_mode.persona_switched"
        ).count
    end
  end

  test "ordinary user cannot use the persona switch endpoint" do
    user = create_user

    with_developer_mode(enabled: true) do
      Operations::DeveloperScenarioSeeder.call(
        scenario: "personas"
      )
      sign_in_as(user)

      switch_persona("owner")

      assert_response :forbidden
      assert_equal user.id, authenticated_session.user_id
    end
  end

  private

  def switch_persona(persona)
    post developer_mode_switch_persona_path,
      params: { persona: persona },
      headers: frontend_application_request_headers(
        application_id: "account",
        referer: account_url
      )
  end

  def authenticated_session
    token = session[Authentication::SESSION_COOKIE]
    assert token.present?, "Expected the integration client to retain a session token"

    Session.find_by_token(token) || flunk("Expected the session token to resolve")
  end

  def with_developer_mode(enabled:)
    settings = Mcweb::DeveloperMode.parse(
      config: {
        developer_mode: {
          enabled: enabled
        }
      },
      environment: {}
    )
    previous =
      Mcweb::DeveloperMode.instance_variable_get(:@settings)
    Mcweb::DeveloperMode.instance_variable_set(:@settings, settings)
    yield
  ensure
    Mcweb::DeveloperMode.instance_variable_set(:@settings, previous)
  end
end
