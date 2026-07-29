# frozen_string_literal: true

require "test_helper"

class DeveloperModeVisibilityTest < ActionDispatch::IntegrationTest
  test "enabled mode is visible in response headers and readiness output" do
    with_unrestricted_developer_mode do
      get health_live_path
      assert_response :ok
      assert_equal "unrestricted", response.headers["X-McWeb-Developer-Mode"]
      assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_equal true, response.parsed_body.fetch("developer_mode")
      assert_equal "unrestricted",
        response.parsed_body.fetch("developer_mode_profile")
      assert_equal false,
        response.parsed_body.fetch("scheduled_jobs_auto_registration")

      get health_ready_path
      assert_includes [ 200, 503 ], response.status
      assert_equal true, response.parsed_body.fetch("developer_mode")
      assert_equal "unrestricted",
        response.parsed_body.fetch("developer_mode_profile")
      assert_equal false,
        response.parsed_body.fetch("scheduled_jobs_auto_registration")
      assert_equal "unrestricted", response.headers["X-McWeb-Developer-Mode"]
      assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
      assert_equal "no-store", response.headers["Cache-Control"]
    end
  end

  test "disabled mode does not emit the developer response header" do
    get health_live_path

    assert_response :ok
    assert_nil response.headers["X-McWeb-Developer-Mode"]
    assert_nil response.headers["X-Robots-Tag"]
    assert_equal false, response.parsed_body.fetch("developer_mode")
    assert_nil response.parsed_body.fetch("developer_mode_profile")
    assert_equal true,
      response.parsed_body.fetch("scheduled_jobs_auto_registration")
  end

  test "enabled mode bypasses the modern browser gate" do
    legacy_browser = {
      "User-Agent" => "Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.0)"
    }

    get identity_sign_in_path, headers: legacy_browser
    assert_response :not_acceptable

    with_unrestricted_developer_mode do
      get identity_sign_in_path, headers: legacy_browser
      assert_response :success
    end
  end

  test "enabled mode preserves an endpoint private cache classification" do
    controller = ApplicationController.new
    test_response = ActionDispatch::TestResponse.new
    controller.set_response!(test_response)
    test_response.set_header("Cache-Control", "private, max-age=0")

    with_unrestricted_developer_mode do
      controller.send(:mark_developer_mode_response)
      test_response.commit!
    end

    assert_includes test_response.headers.fetch("Cache-Control"), "private"
    assert_includes test_response.headers.fetch("Cache-Control"), "no-store"
    assert_not_includes test_response.headers.fetch("Cache-Control"), "public"
  end

  private

  def with_unrestricted_developer_mode
    settings = Mcweb::DeveloperMode.parse(
      config: { developer_mode: { enabled: true } },
      environment: {}
    )
    previous_settings = Mcweb::DeveloperMode.instance_variable_get(:@settings)
    Mcweb::DeveloperMode.instance_variable_set(:@settings, settings)
    yield
  ensure
    Mcweb::DeveloperMode.instance_variable_set(:@settings, previous_settings)
  end
end
