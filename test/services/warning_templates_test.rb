# frozen_string_literal: true

require "test_helper"

class WarningTemplateTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.users.warn")
    @user = create_user
  end

  test "validates name presence and point range" do
    assert_not Community::WarningTemplate.new(name: "", points: 1).valid?
    assert_not Community::WarningTemplate.new(name: "x", points: 99).valid?
    assert Community::WarningTemplate.new(name: "Spam", points: 3).valid?
  end

  test "CreateUserWarning applies a template's defaults" do
    template = Community::WarningTemplate.create!(name: "Spam", reason: "Spamming the forum", points: 4, expire_days: 30)
    result = Community::CreateUserWarning.call(actor: @mod, user: @user, template_id: template.id)

    assert result.success?
    warning = result.value
    assert_equal "Spamming the forum", warning.reason
    assert_equal 4, warning.points
    assert warning.expires_at.present?
  end

  test "explicit values override the template" do
    template = Community::WarningTemplate.create!(name: "Spam", reason: "Spamming", points: 4)
    result = Community::CreateUserWarning.call(actor: @mod, user: @user, reason: "Custom reason", points: 2, template_id: template.id)

    assert result.success?
    assert_equal "Custom reason", result.value.reason
    assert_equal 2, result.value.points
  end
end
