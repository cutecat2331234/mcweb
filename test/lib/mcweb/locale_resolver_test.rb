# frozen_string_literal: true

require "test_helper"

class Mcweb::LocaleResolverTest < ActiveSupport::TestCase
  test "normalizes supported aliases and falls back for invalid legacy values" do
    assert_equal "zh-CN", Mcweb::LocaleResolver.normalize("zh_Hans")
    assert_equal "en", Mcweb::LocaleResolver.normalize("EN-us")
    assert_nil Mcweb::LocaleResolver.normalize("fr")
    assert_equal I18n.default_locale.to_s, Mcweb::LocaleResolver.resolve("legacy-invalid")
  end

  test "user locales are canonicalized and unsupported values are rejected" do
    user = create_user(locale: "en_US")
    assert_equal "en", user.locale

    user.locale = "fr"
    assert_not user.valid?
    assert user.errors.added?(:locale, :inclusion, value: "fr")
  end
end
