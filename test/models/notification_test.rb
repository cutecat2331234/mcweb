# frozen_string_literal: true

require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  test "destination path treats non-object metadata as empty" do
    assert_nil Notification.new(metadata: []).destination_path
    assert_nil Notification.new(metadata: "invalid").destination_path
    assert_nil Notification.new(metadata: nil).destination_path
  end
end
