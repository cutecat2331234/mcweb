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
end
