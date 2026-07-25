# frozen_string_literal: true

require "test_helper"

class CeRealtimeEditionBoundaryTest < ActiveSupport::TestCase
  FRONTEND_EXTENSIONS = %w[.js .jsx .ts .tsx .vue].freeze
  REALTIME_COMPOSABLE_NAME = /\Ause.*(?:cable|realtime|socket|stream|typing|websocket)/i
  BUSINESS_BROADCAST = /
    ActionCable\.server\.broadcast |
    (?:\b[A-Z]\w*(?:::\w+)*Channel)\.broadcast(?:_to)? |
    \.broadcast_to
  /x

  # Gemfile.lock can retain actioncable transitively through the Rails meta-gem,
  # while config/database.yml and db/*cable* are adapter/storage declarations.
  # None of those files exposes a browser endpoint by itself, so this boundary
  # intentionally checks loaded runtime configuration and executable app code.
  test "CE has no loaded Action Cable mount or business channel" do
    action_cable_config =
      Rails.application.config.action_cable if Rails.application.config.respond_to?(:action_cable)

    assert_nil action_cable_config

    # ApplicationCable base classes are framework scaffolding rather than a
    # business stream. The mount assertion above prevents that scaffolding from
    # becoming reachable; every other channel file is edition functionality.
    business_channels = Rails.root.glob("app/channels/**/*.rb").reject do |path|
      relative_path(path).start_with?("app/channels/application_cable/")
    end

    assert_empty business_channels.map { |path| relative_path(path) }
  end

  test "CE has no realtime frontend composable" do
    composables = frontend_sources.select do |path|
      path.basename.to_s.match?(REALTIME_COMPOSABLE_NAME)
    end

    assert_empty composables.map { |path| relative_path(path) }
  end

  test "CE app code has no business channel broadcast" do
    broadcast_sources = Rails.root.glob("app/**/*.rb").select do |path|
      path.file? && path.read.match?(BUSINESS_BROADCAST)
    end

    assert_empty broadcast_sources.map { |path| relative_path(path) }
  end

  private

  def frontend_sources
    Rails.root.glob("app/javascript/**/*").select do |path|
      path.file? && FRONTEND_EXTENSIONS.include?(path.extname)
    end
  end

  def relative_path(path)
    path.relative_path_from(Rails.root).to_s.tr("\\", "/")
  end
end
