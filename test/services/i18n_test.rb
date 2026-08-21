# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class I18nZhCNTest < ActiveSupport::TestCase
  test "user password blank error is translated in zh-CN" do
    I18n.with_locale("zh-CN") do
      user = User.new(email: "test@example.com", username: "testuser", locale: "zh-CN", time_zone: "Asia/Shanghai")
      user.password = ""
      assert_not user.valid?
      assert_includes user.errors[:password], "不能为空"
    end
  end

  test "user password blank full message includes attribute name" do
    I18n.with_locale("zh-CN") do
      user = User.new(email: "test@example.com", username: "testuser", locale: "zh-CN", time_zone: "Asia/Shanghai")
      user.password = ""
      user.valid?
      assert_match(/密码/, user.errors.full_messages.join)
    end
  end

  test "register user failure returns translated errors" do
    I18n.with_locale("zh-CN") do
      Rails.cache.clear
      result = Identity::RegisterUser.call(
        email: "a@b.com",
        username: "abuser#{SecureRandom.hex(3)}",
        password: "",
        ip_address: "127.0.0.1"
      )
      assert result.failure?
      password_errors = result.errors[:password] || result.errors["password"]
      assert password_errors&.any? { |m| m.include?("不能为空") }
    end
  end

  test "order status labels respect locale" do
    I18n.with_locale("zh-CN") do
      assert_equal "待支付", I18n.t("mcweb.labels.order_status.pending")
    end
    I18n.with_locale(:en) do
      assert_equal "Pending payment", I18n.t("mcweb.labels.order_status.pending")
    end
  end

  test "subscription notices respect locale" do
    I18n.with_locale(:en) do
      assert_equal "Watching this topic (instant notifications).",
                   I18n.t("mcweb.flash.subscription.watching.topic")
    end
  end

  test "boolean-like YAML keys remain addressable in every locale" do
    keys = %w[
      mcweb.flash.subscription.off.topic
      mcweb.labels.yes
      mcweb.labels.no
    ]

    I18n.available_locales.each do |locale|
      I18n.with_locale(locale) do
        keys.each do |key|
          assert I18n.exists?(key), "#{locale} is missing #{key}"
          refute_match(/\ATranslation missing:/, I18n.t(key))
        end
      end
    end
  end

  test "notification type labels respect locale" do
    I18n.with_locale("zh-CN") do
      assert_equal "主题回复", Community::NotificationTypeLabels.label_for("forum.topic_reply")
    end
    I18n.with_locale(:en) do
      assert_equal "Topic reply", Community::NotificationTypeLabels.label_for("forum.topic_reply")
    end
  end

  test "mail templates respect locale" do
    I18n.with_locale("zh-CN") do
      assert_includes I18n.t("mcweb.mail.forum.topic_reply.body", author: "alice", title: "Hello"), "alice"
      assert_includes I18n.t("mcweb.mail.identity.verification.intro"), "验证"
    end
    I18n.with_locale(:en) do
      assert_includes I18n.t("mcweb.mail.forum.topic_reply.body", author: "alice", title: "Hello"), "alice"
      assert_includes I18n.t("mcweb.mail.identity.verification.intro"), "verify"
    end
  end

  test "commerce mail templates respect locale" do
    I18n.with_locale("zh-CN") do
      assert_includes I18n.t("mcweb.mail.commerce.payment_confirmed.body", number: "A001"), "A001"
      assert_includes I18n.t("mcweb.mail.commerce.order_shipped.heading"), "发货"
    end
    I18n.with_locale(:en) do
      assert_includes I18n.t("mcweb.mail.commerce.payment_confirmed.body", number: "A001"), "A001"
      assert_includes I18n.t("mcweb.mail.commerce.order_shipped.heading"), "shipped"
    end
  end
end

class I18nLocaleSwitchTest < ActionDispatch::IntegrationTest
  test "locale controller updates session and user locale" do
    user = create_user
    sign_in_as(user)

    patch locale_path, params: { locale: "en" }
    assert_redirected_to root_path
    assert_equal "en", session[:locale]
    assert_equal "en", user.reload.locale
  end

  test "invalid locale is rejected" do
    patch locale_path, params: { locale: "fr" }
    assert_redirected_to root_path
    assert_nil session[:locale]
  end

  test "locale switch removes a conflicting locale from the return URL" do
    patch locale_path,
      params: { locale: "zh-CN" },
      headers: { "HTTP_REFERER" => "http://www.example.com/app/forum?locale=en&tab=latest#topic" }

    assert_redirected_to "/app/forum?tab=latest#topic"
    assert_equal "zh-CN", session[:locale]
  end

  test "inertia navigation honors the shared frontend locale preference" do
    patch locale_path, params: { locale: "zh-CN" }

    get identity_sign_in_path,
      headers: inertia_headers.merge("X-McWeb-Locale" => "en")

    assert_response :success
    assert_equal "en", inertia.props.deep_symbolize_keys[:locale]
  end

  test "explicit locale takes precedence over the inertia locale header" do
    get identity_sign_in_path,
      params: { locale: "zh-CN" },
      headers: inertia_headers.merge("X-McWeb-Locale" => "en")

    assert_response :success
    assert_equal "zh-CN", inertia.props.deep_symbolize_keys[:locale]
  end

  test "non-inertia requests ignore the frontend locale header" do
    patch locale_path, params: { locale: "zh-CN" }

    get identity_sign_in_path, headers: { "X-McWeb-Locale" => "en" }

    assert_response :success
    assert_match(/<html\s+lang="zh-CN"/, response.body)
  end

  private

  def inertia_headers
    {
      "X-Inertia" => "true",
      "X-Inertia-Version" => InertiaRails.configuration.version
    }
  end
end
