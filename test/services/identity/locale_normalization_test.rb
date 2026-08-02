# frozen_string_literal: true

require "test_helper"

class Identity::LocaleNormalizationTest < ActiveSupport::TestCase
  test "registration persists a canonical supported locale" do
    result = Identity::RegisterUser.call(
      email: "locale-#{SecureRandom.hex(5)}@example.com",
      username: "locale_#{SecureRandom.hex(5)}",
      password: "password123",
      locale: "EN-gb"
    )

    assert_predicate result, :success?
    assert_equal "en", result.value.fetch(:user).locale
  end

  test "registration rejects unsupported locales" do
    result = Identity::RegisterUser.call(
      email: "unsupported-locale-#{SecureRandom.hex(5)}@example.com",
      username: "badlocale_#{SecureRandom.hex(4)}",
      password: "password123",
      locale: "fr"
    )

    assert_predicate result, :failure?
    assert_includes result.errors.keys, :locale
  end
end
