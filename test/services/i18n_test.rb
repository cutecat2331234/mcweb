# frozen_string_literal: true

require "test_helper"

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
      result = Identity::RegisterUser.call(email: "a@b.com", username: "abuser", password: "")
      assert result.failure?
      assert result.errors[:password].any? { |m| m.include?("不能为空") }
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
end
