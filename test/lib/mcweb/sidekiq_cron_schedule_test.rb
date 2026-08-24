# frozen_string_literal: true

require "test_helper"
require "tempfile"

class Mcweb::SidekiqCronScheduleTest < ActiveSupport::TestCase
  SchedulerConfiguration = Struct.new(:enabled, :cron_poll_interval)

  test "developer mode disables schedule loading and the cron poller" do
    configuration = SchedulerConfiguration.new(true, 30)

    enabled = Mcweb::SidekiqCronSchedule.configure_scheduler!(
      configuration: configuration,
      settings: developer_settings(enabled: true)
    )

    assert_equal false, enabled
    assert_equal false, configuration.enabled
    assert_equal 0, configuration.cron_poll_interval
  end

  test "disabled developer mode does not mutate scheduler configuration" do
    configuration = SchedulerConfiguration.new(:existing, 47)

    enabled = Mcweb::SidekiqCronSchedule.configure_scheduler!(
      configuration: configuration,
      settings: developer_settings(enabled: false)
    )

    assert_equal true, enabled
    assert_equal :existing, configuration.enabled
    assert_equal 47, configuration.cron_poll_interval
  end

  test "developer mode skips schedule parsing and automatic registration" do
    settings = developer_settings(enabled: true)
    yielded = false

    Tempfile.create([ "invalid-sidekiq-cron", ".yml" ]) do |file|
      file.write("invalid: [")
      file.flush

      result = Mcweb::SidekiqCronSchedule.register!(
        schedule_path: file.path,
        settings: settings
      ) do
        yielded = true
      end

      assert_equal :disabled_by_developer_mode, result.status
      assert_equal 0, result.job_count
      assert_not yielded
    end
  end

  test "disabled developer mode preserves normal schedule loading" do
    settings = developer_settings(enabled: false)
    loaded_schedule = nil

    Tempfile.create([ "sidekiq-cron", ".yml" ]) do |file|
      file.write(<<~YAML)
        cleanup:
          cron: "0 * * * *"
          class: "Maintenance::CleanupJob"
        digest:
          cron: "0 8 * * *"
          class: "Community::DigestJob"
      YAML
      file.flush

      result = Mcweb::SidekiqCronSchedule.register!(
        schedule_path: file.path,
        settings: settings
      ) do |schedule|
        loaded_schedule = schedule
      end

      assert_equal :registered, result.status
      assert_equal 2, result.job_count
      assert_equal %w[cleanup digest], loaded_schedule.keys
    end
  end

  test "missing schedule remains a no-op outside developer mode" do
    result = Mcweb::SidekiqCronSchedule.register!(
      schedule_path: Rails.root.join("tmp/does-not-exist-sidekiq-cron.yml"),
      settings: developer_settings(enabled: false)
    ) do
      flunk "a missing schedule must not be loaded"
    end

    assert_equal :missing, result.status
    assert_equal 0, result.job_count
  end

  test "initializer delegates registration without removing the manual dashboard" do
    initializer = Rails.root.join("config/initializers/sidekiq.rb").read
    routes = Rails.root.join("config/routes.rb").read

    assert_includes initializer, "Mcweb::SidekiqCronSchedule.configure_scheduler!"
    assert_includes initializer, "Mcweb::SidekiqCronSchedule.register!"
    assert_includes initializer, "Sidekiq::Cron::Job.load_from_hash!"
    assert_includes initializer,
      'Sidekiq::Web.app_url = "/admin/system/sidekiq"'
    assert_includes routes,
      'mount Mcweb::SidekiqWebFramePolicy.new(Sidekiq::Web), at: "/jobs"'
  end

  private

  def developer_settings(enabled:)
    Mcweb::DeveloperMode.parse(
      config: { developer_mode: { enabled: enabled } },
      environment: {}
    )
  end
end
