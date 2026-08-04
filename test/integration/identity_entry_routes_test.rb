# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class IdentityEntryRoutesTest < ActionDispatch::IntegrationTest
  test "public identity entry URLs render their forms without a new suffix" do
    {
      "/app/identity/register" => "Identity/Registrations/New",
      "/app/identity/password_resets" => "Identity/PasswordResets/New",
      "/app/identity/resend-verification" => "Identity/EmailVerificationResends/New"
    }.each do |path, component|
      get path

      assert_response :success, path
      assert_equal component, inertia.component, path
    end
  end
end
