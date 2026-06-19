# frozen_string_literal: true

require "test_helper"

class IdentityRegistrationsTest < ActionDispatch::IntegrationTest
  test "duplicate email returns validation errors in props" do
    create_user(email: "taken@example.com", username: "takenuser")

    post identity_registrations_path, params: {
      registration: {
        email: "taken@example.com",
        username: "newuser123",
        password: "password123",
        display_name: "New"
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "form_errors"
    assert_includes response.body, "registration.email"
  end
end
