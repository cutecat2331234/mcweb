# frozen_string_literal: true

require "test_helper"

class DeveloperModePersonaSwitchTest < ActionDispatch::IntegrationTest
  test "route is hidden before authentication when Developer Mode is disabled" do
    with_developer_mode(enabled: false) do
      post developer_mode_switch_persona_path,
        params: { persona: "member" }

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

      post developer_mode_switch_persona_path,
        params: { persona: "member" }
      assert_redirected_to Mcweb::Paths::APP_PREFIX

      member = User.find_by!(developer_mode_persona: "member")
      assert_equal member.id,
        Session.active.order(:id).last.user_id

      post developer_mode_switch_persona_path,
        params: { persona: "owner" }
      assert_redirected_to Mcweb::Paths::APP_PREFIX

      owner = User.find_by!(developer_mode_persona: "owner")
      assert_equal owner.id,
        Session.active.order(:id).last.user_id
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

      post developer_mode_switch_persona_path,
        params: { persona: "owner" }

      assert_response :forbidden
      assert_not_equal(
        User.find_by!(developer_mode_persona: "owner").id,
        Session.active.order(:id).last.user_id
      )
    end
  end

  private

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
