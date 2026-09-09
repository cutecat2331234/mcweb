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
    assert_equal "en", session[LocaleSettable::LOCALE_EXPLICIT_SESSION_KEY]
    assert_equal "en", cookies[LocaleSettable::LOCALE_EXPLICIT_COOKIE]
    assert_equal "en", user.reload.locale
  end

  test "invalid locale is rejected" do
    patch locale_path, params: { locale: "en" }
    assert_redirected_to root_path
    assert_equal "en", session[:locale]

    patch locale_path, params: { locale: "fr" }
    assert_redirected_to root_path
    assert_equal "en", session[:locale]
    assert_equal "en", session[LocaleSettable::LOCALE_EXPLICIT_SESSION_KEY]
    assert_equal "en", cookies[LocaleSettable::LOCALE_EXPLICIT_COOKIE]
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
    assert_equal "en", session[:locale]

    get identity_sign_in_path

    assert_response :success
    assert_match(/<html\s+lang="en"/, response.body)
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

  test "signed-in explicit locale survives a native cross-application document navigation" do
    SiteSetting.set("features.forum.enabled", "true")
    user = create_user(locale: "en")
    sign_in_as(user)

    get account_path, params: { locale: "zh-CN" }

    assert_response :success
    assert_equal "zh-CN", inertia.props.deep_symbolize_keys[:locale]
    assert_equal "zh-CN", session[:locale]
    assert_equal "en", user.reload.locale

    get forum_sections_path

    assert_response :success
    assert_equal "Community/Sections/Index", inertia.component
    assert_equal "zh-CN", inertia.props.deep_symbolize_keys[:locale]
    assert_equal "zh-CN", session[:locale]
  end

  test "sign in adopts the account locale when the guest bridge was only implicit" do
    user = create_user(locale: "en")

    sign_in_as(user)
    get account_path

    assert_response :success
    assert_equal "en", inertia.props.deep_symbolize_keys[:locale]
    assert_equal "en", session[:locale]
  end

  test "an explicit signed-out locale remains selected after sign in" do
    user = create_user(locale: "zh-CN")
    patch locale_path, params: { locale: "en" }

    sign_in_as(user)
    get account_path

    assert_response :success
    assert_equal "en", inertia.props.deep_symbolize_keys[:locale]
    assert_equal "en", session[:locale]
    assert_equal "zh-CN", user.reload.locale
  end

  test "an explicit static-renderer cookie survives sign in and converges the session" do
    user = create_user(locale: "zh-CN")
    cookies[LocaleSettable::LOCALE_COOKIE] = "en"
    cookies[LocaleSettable::LOCALE_EXPLICIT_COOKIE] = "en"

    sign_in_as(user)
    get account_path

    assert_response :success
    assert_equal "en", inertia.props.deep_symbolize_keys[:locale]
    assert_equal "en", session[:locale]
    assert_equal "zh-CN", user.reload.locale
  end

  private

  def inertia_headers
    {
      "X-Inertia" => "true",
      "X-Inertia-Version" => InertiaRails.configuration.version
    }
  end
end

class LocaleResolutionHarness
  def self.around_action(*_args)
  end

  include LocaleSettable

  attr_reader :params, :session, :cookies, :request

  def initialize(params: {}, session: {}, cookies: {}, user: nil, headers: {}, accept_language: nil)
    @params = params
    @session = session
    @cookies = cookies
    @user = user
    @request = Struct.new(:headers, :env).new(
      headers,
      { "HTTP_ACCEPT_LANGUAGE" => accept_language }
    )
  end

  def logged_in?
    @user.present?
  end

  def current_user
    @user
  end

  public :resolved_locale
end

class I18nLocaleResolutionPriorityTest < ActiveSupport::TestCase
  test "account locale remains the fallback when no locale bridge exists" do
    user = Struct.new(:locale).new("en")
    resolver = LocaleResolutionHarness.new(user: user)

    assert_equal "en", resolver.resolved_locale
  end

  test "only an explicit shared cookie supersedes a stale session and both precede the account locale" do
    user = Struct.new(:locale).new("en")

    implicit_resolver = LocaleResolutionHarness.new(
      session: { locale: "zh-CN" },
      cookies: { LocaleSettable::LOCALE_COOKIE => "en" },
      user: user
    )
    explicit_resolver = LocaleResolutionHarness.new(
      session: { locale: "zh-CN" },
      cookies: {
        LocaleSettable::LOCALE_COOKIE => "en",
        LocaleSettable::LOCALE_EXPLICIT_COOKIE => "en"
      },
      user: user
    )
    signed_in_cookie_resolver = LocaleResolutionHarness.new(
      cookies: { LocaleSettable::LOCALE_COOKIE => "zh-CN" },
      user: user
    )
    anonymous_cookie_resolver = LocaleResolutionHarness.new(
      cookies: { LocaleSettable::LOCALE_COOKIE => "zh-CN" }
    )

    assert_equal "zh-CN", implicit_resolver.resolved_locale
    assert_equal "en", explicit_resolver.resolved_locale
    assert_equal "en", signed_in_cookie_resolver.resolved_locale
    assert_equal "zh-CN", anonymous_cookie_resolver.resolved_locale
  end

  test "an old explicit marker cannot promote a later implicit cookie rewrite" do
    user = Struct.new(:locale).new("en")
    resolver = LocaleResolutionHarness.new(
      session: {
        locale: "en",
        LocaleSettable::LOCALE_EXPLICIT_SESSION_KEY => "en"
      },
      cookies: {
        LocaleSettable::LOCALE_COOKIE => "zh-CN",
        LocaleSettable::LOCALE_EXPLICIT_COOKIE => "en"
      },
      user: user
    )
    orphaned_cookie_marker = LocaleResolutionHarness.new(
      cookies: {
        LocaleSettable::LOCALE_COOKIE => "zh-CN",
        LocaleSettable::LOCALE_EXPLICIT_COOKIE => "1"
      },
      user: user
    )

    assert_equal "en", resolver.resolved_locale
    assert_equal "en", orphaned_cookie_marker.resolved_locale
  end

  test "an earlier session marker cannot promote an implicit cookie after a newer static choice" do
    resolver = LocaleResolutionHarness.new(
      session: {
        locale: "zh-CN",
        LocaleSettable::LOCALE_EXPLICIT_SESSION_KEY => "en"
      },
      cookies: {
        LocaleSettable::LOCALE_COOKIE => "en",
        LocaleSettable::LOCALE_EXPLICIT_COOKIE => "zh-CN"
      }
    )

    assert_equal "zh-CN", resolver.resolved_locale
  end

  test "explicit locale and genuine Inertia headers precede the current bridge" do
    inertia_headers = {
      "X-Inertia" => "true",
      "X-McWeb-Locale" => "en"
    }

    explicit_resolver = LocaleResolutionHarness.new(
      params: { locale: "zh-CN" },
      session: { locale: "en" },
      headers: inertia_headers
    )
    inertia_resolver = LocaleResolutionHarness.new(
      session: { locale: "zh-CN" },
      headers: inertia_headers
    )
    non_inertia_resolver = LocaleResolutionHarness.new(
      session: { locale: "zh-CN" },
      headers: inertia_headers.merge("X-Inertia" => "false")
    )

    assert_equal "zh-CN", explicit_resolver.resolved_locale
    assert_equal "en", inertia_resolver.resolved_locale
    assert_equal "zh-CN", non_inertia_resolver.resolved_locale
  end
end
