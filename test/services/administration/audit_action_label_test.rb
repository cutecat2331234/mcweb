# frozen_string_literal: true

require "test_helper"

module Administration
  class AuditActionLabelTest < ActiveSupport::TestCase
    test "common audit actions have human-readable labels in every product locale" do
      expected = {
        en: {
          "system.developer_mode_configuration_changed" => "Developer Mode configuration changed",
          "identity.sign_in" => "User signed in",
          "community.post_created" => "Forum post created"
        },
        "zh-CN": {
          "system.developer_mode_configuration_changed" => "已更新开发模式配置",
          "identity.sign_in" => "用户已登录",
          "community.post_created" => "已发布论坛帖子"
        }
      }

      expected.each do |locale, labels|
        labels.each do |action, label|
          assert_equal label, AuditActionLabel.call(action, locale:), "#{locale}: #{action}"
        end
      end
    end

    test "audit action translation catalogs stay aligned across locales" do
      english = I18n.t("mcweb.audit.actions", locale: :en)
      chinese = I18n.t("mcweb.audit.actions", locale: :"zh-CN")

      assert_kind_of Hash, english
      assert_kind_of Hash, chinese
      assert_equal english.keys.map(&:to_s).sort, chinese.keys.map(&:to_s).sort
      assert english.values.all?(&:present?)
      assert chinese.values.all?(&:present?)
    end

    test "unknown and blank action codes have safe deterministic fallbacks" do
      assert_equal "Custom event · Future state",
                   AuditActionLabel.call("custom_event.future-state", locale: :en)
      assert_equal I18n.t("mcweb.labels.not_available", locale: :"zh-CN"),
                   AuditActionLabel.call("  ", locale: :"zh-CN")
    end
  end
end
