# frozen_string_literal: true

require "test_helper"

class CeRealtimeEditionBoundaryTest < ActiveSupport::TestCase
  FRONTEND_EXTENSIONS = %w[.js .jsx .ts .tsx .vue].freeze
  REALTIME_COMPOSABLE_NAME = /\Ause.*(?:cable|realtime|socket|stream|typing|websocket)/i
  BUSINESS_BROADCAST = /
    ActionCable\.server\.broadcast |
    (?:\b[A-Z]\w*(?:::\w+)*Channel)\.broadcast(?:_to)? |
    \.broadcast_(?:append|prepend|remove|replace|update)_to |
    \.broadcast_to |
    \bstream_(?:from|for)\b
  /x

  # Gemfile.lock can retain actioncable transitively through the Rails meta-gem,
  # while config/database.yml and db/*cable* are adapter/storage declarations.
  # None of those files exposes a browser endpoint by itself, so this boundary
  # intentionally checks loaded runtime configuration and executable app code.
  test "CE has no loaded Action Cable mount or channel file" do
    action_cable_config =
      Rails.application.config.action_cable if Rails.application.config.respond_to?(:action_cable)

    assert_nil action_cable_config

    # CE deliberately keeps even the generated ApplicationCable scaffolding
    # absent. A channel base class is otherwise an easy place for EE-only
    # runtime code to be reintroduced accidentally.
    channel_files = Rails.root.glob("app/channels/**/*").select(&:file?)

    assert_empty channel_files.map { |path| relative_path(path) }
  end

  test "CE has no realtime frontend composable" do
    composables = frontend_sources.select do |path|
      path.basename.to_s.match?(REALTIME_COMPOSABLE_NAME)
    end

    assert_empty composables.map { |path| relative_path(path) }
  end

  test "CE app code has no business channel broadcast" do
    broadcast_sources = Rails.root.glob("{app,config,lib}/**/*.rb").select do |path|
      path.file? && path.read.match?(BUSINESS_BROADCAST)
    end

    assert_empty broadcast_sources.map { |path| relative_path(path) }
  end

  test "CE views and dependencies do not boot a realtime browser transport" do
    view_sources = Rails.root.glob("app/views/**/*").select(&:file?)
    action_cable_views = view_sources.select do |path|
      path.read.match?(/\baction_cable_meta_tag\b|\bActionCable\b/)
    end

    assert_empty action_cable_views.map { |path| relative_path(path) }
    assert_no_match(/@rails\/actioncable|actioncable/i, Rails.root.join("package.json").read)
    assert_no_match(/gem\s+["']solid_cable["']/, Rails.root.join("Gemfile").read)
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
