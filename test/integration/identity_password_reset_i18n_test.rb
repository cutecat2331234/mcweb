# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class IdentityPasswordResetI18nTest < ActionDispatch::IntegrationTest
  test "password confirmation mismatch follows the request locale" do
    {
      "en" => "en",
      "zh-CN" => "zh-CN"
    }.each do |accept_language, locale|
      patch identity_password_reset_path("reset-token"), params: {
        password_reset: {
          password: "password456",
          password_confirmation: "different456"
        }
      }, headers: {
        "Accept-Language" => accept_language
      }

      assert_response :unprocessable_entity
      assert_equal(
        I18n.t(
          "mcweb.services.errors.password_confirmation_mismatch",
          locale: locale
        ),
        inertia.props.deep_symbolize_keys.dig(:form_errors, :base)
      )
    end
  end
end
