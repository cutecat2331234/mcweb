# frozen_string_literal: true

require "test_helper"

class ServiceErrorTranslatorTest < ActiveSupport::TestCase
  test "translates exact service errors in zh-CN" do
    I18n.with_locale("zh-CN") do
      assert_equal "找不到该用户。", ServiceErrorTranslator.translate("Recipient not found.")
      assert_equal "消息内容不能为空。", ServiceErrorTranslator.translate("Message is too short.")
    end
  end

  test "translates patterned errors in zh-CN" do
    I18n.with_locale("zh-CN") do
      assert_equal "无法向 alice 发送私信。", ServiceErrorTranslator.translate("You cannot message alice.")
      assert_equal "找不到以下用户：bob, carol", ServiceErrorTranslator.translate("Users not found: bob, carol")
    end
  end

  test "translates commerce and poll errors in zh-CN" do
    I18n.with_locale("zh-CN") do
      assert_equal "投票已关闭。", ServiceErrorTranslator.translate("Poll is closed.")
      assert_equal "该订单无法取消。", ServiceErrorTranslator.translate("Order cannot be cancelled.")
    end
  end

  test "translates slug service error keys in zh-CN" do
    I18n.with_locale("zh-CN") do
      assert_equal "会员履约失败。", ServiceErrorTranslator.translate("membership_fulfillment_failed")
      assert_equal "订单含需自动履约的项目（含会员商品），不可手动标记发货完成。",
                   ServiceErrorTranslator.translate("automated_fulfillment_required")
    end
  end

  test "translates exact service errors in en" do
    I18n.with_locale(:en) do
      assert_equal "Recipient not found.", ServiceErrorTranslator.translate("Recipient not found.")
      assert_equal "Poll is closed.", ServiceErrorTranslator.translate("Poll is closed.")
    end
  end
end
