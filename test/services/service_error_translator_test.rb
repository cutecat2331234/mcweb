# frozen_string_literal: true

require "test_helper"

class ServiceErrorTranslatorTest < ActiveSupport::TestCase
  test "translates exact service errors" do
    assert_equal "找不到该用户。", ServiceErrorTranslator.translate("Recipient not found.")
    assert_equal "消息内容不能为空。", ServiceErrorTranslator.translate("Message is too short.")
  end

  test "translates patterned errors" do
    assert_equal "无法向 alice 发送私信。", ServiceErrorTranslator.translate("You cannot message alice.")
    assert_equal "找不到以下用户：bob, carol", ServiceErrorTranslator.translate("Users not found: bob, carol")
  end

  test "translates commerce and poll errors" do
    assert_equal "投票已关闭。", ServiceErrorTranslator.translate("Poll is closed.")
    assert_equal "该订单无法取消。", ServiceErrorTranslator.translate("Order cannot be cancelled.")
  end
end
