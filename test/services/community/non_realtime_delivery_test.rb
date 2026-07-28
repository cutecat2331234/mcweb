# frozen_string_literal: true

require "test_helper"

class Community::NonRealtimeDeliveryTest < ActiveSupport::TestCase
  CHANNEL_PATHS = %w[
    app/channels/application_cable/channel.rb
    app/channels/application_cable/connection.rb
    app/channels/community/conversation_channel.rb
    app/channels/community/notifications_channel.rb
  ].freeze

  FORBIDDEN_BACKEND_PATTERNS = {
    "Action Cable reference" => /\bActionCable\b/,
    "application cable namespace" => /\bApplicationCable\b/,
    "channel broadcast" => /\.broadcast_to\s*\(/,
    "server broadcast" => /\.server\.broadcast\s*\(/
  }.freeze

  setup do
    @sender = create_user
    @recipient = create_user
    enable_forum_pm!(@sender)
  end

  test "CE has no Action Cable backend infrastructure or publisher calls" do
    CHANNEL_PATHS.each do |relative_path|
      refute_path_exists Rails.root.join(relative_path)
    end

    backend_sources.each do |path|
      source = File.read(path)
      FORBIDDEN_BACKEND_PATTERNS.each do |label, pattern|
        refute_match pattern, source, "#{label} remains in #{path.relative_path_from(Rails.root)}"
      end
    end

    refute_includes File.read(Rails.root.join("config/application.rb")), 'require "action_cable/engine"'
    refute_includes File.read(Rails.root.join("Gemfile")), 'gem "solid_cable"'
    refute_path_exists Rails.root.join("config/cable.yml")
    refute_path_exists Rails.root.join("db/cable_schema.rb")
  end

  test "notifications remain persisted for polling" do
    notification = nil

    assert_difference -> { Notification.where(user: @recipient).count }, 1 do
      notification = Notification.notify!(
        user: @recipient,
        notification_type: "forum.mention",
        title: "Persistent notification",
        metadata: { path: "/app/forum/notifications" }
      )
    end

    assert_predicate notification, :persisted?
    assert_equal "/app/forum/notifications", notification.destination_path
    assert_not_respond_to Notification, :broadcast_new
  end

  test "private messages and their notifications remain persisted" do
    conversation = Community::Conversation.create!(creator: @sender)
    conversation.participants.create!(user: @sender)
    conversation.participants.create!(user: @recipient)
    result = nil

    assert_difference -> { conversation.messages.count }, 1 do
      assert_difference(
        -> { Notification.where(user: @recipient, notification_type: "forum.private_message").count },
        1
      ) do
        result = Community::SendMessage.call(
          user: @sender,
          conversation: conversation,
          body: "A durable private message"
        )
      end
    end

    assert_predicate result, :success?
    assert_equal "A durable private message", result.value.body
  end

  private

  def backend_sources
    Rails.root.glob("{app,config,lib}/**/*.rb").reject do |path|
      path.to_s.include?("#{File::SEPARATOR}javascript#{File::SEPARATOR}")
    end
  end
end

class Community::NoCableRouteTest < ActionDispatch::IntegrationTest
  REALTIME_ROUTE = %r{/(?:cable|realtime|websocket)(?:[(/.]|$)}i

  test "CE does not mount a realtime transport endpoint" do
    mounted_realtime_routes = Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s
      endpoint = route.app.to_s
      next unless path.match?(REALTIME_ROUTE) || endpoint.match?(/ActionCable|WebSocket/i)

      "#{path} -> #{endpoint}"
    end

    assert_empty mounted_realtime_routes

    %w[/cable /realtime /websocket].each do |path|
      get path
      assert_response :not_found, "#{path} unexpectedly exposed a CE realtime endpoint"
    end
  end
end
