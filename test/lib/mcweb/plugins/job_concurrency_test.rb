# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/job_recovery"
require "mcweb/plugins/registry"
require "tmpdir"

class Mcweb::Plugins::JobConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @root = Pathname(Dir.mktmpdir("mcweb-plugin-job-concurrency"))
    Mcweb::Plugins.reset!
    clear_enqueued_jobs
  end

  teardown do
    Mcweb::Plugins.reset!
    PluginJobRun.delete_all
    clear_enqueued_jobs
    FileUtils.remove_entry(@root) if @root&.exist?
  end

  test "concurrent identical enqueues create one owned run" do
    definition = register_plugin
    outcomes = Queue.new
    ready = Queue.new
    gate = Queue.new
    arguments = {
      recipient_id: SecureRandom.uuid,
      message: "concurrent-secret"
    }

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          gate.pop
          outcomes << definition.api.jobs.enqueue(
            job_key: "deliver",
            arguments:,
            idempotency_key: "delivery:concurrent"
          )
        end
      end
    end
    2.times { ready.pop }
    2.times { gate << true }
    threads.each(&:join)
    results = 2.times.map { outcomes.pop }

    assert results.all?(&:success?)
    assert_equal 1, results.count { |result| result.value.fetch("idempotent") }
    assert_equal 1, PluginJobRun.where(owner_plugin_id: "acme/jobs").count
    assert_equal 1, enqueued_jobs.count { |job| job.fetch(:job) == PluginOwnedJob }
  end

  test "duplicate workers invoke the handler once while a lease is active" do
    entered = Queue.new
    release = Queue.new
    calls = Queue.new
    definition = register_plugin do
      calls << true
      entered << true
      release.pop
    end
    result = definition.api.jobs.enqueue(
      job_key: "deliver",
      arguments: {
        recipient_id: SecureRandom.uuid,
        message: "once"
      },
      idempotency_key: "delivery:worker"
    )
    public_id = result.value.fetch("public_id")

    first = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Mcweb::Plugins::JobRunner.new.perform(public_id)
      end
    end
    entered.pop
    second = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Mcweb::Plugins::JobRunner.new.perform(public_id)
      end
    end
    second.join
    release << true
    first.join

    run = PluginJobRun.find_by!(public_id:)
    assert_equal "succeeded", run.status
    assert_equal 1, run.attempts
    assert_equal 1, calls.size
  end

  test "concurrent recovery sweepers reserve a stale run once" do
    definition = register_plugin
    result = definition.api.jobs.enqueue(
      job_key: "deliver",
      arguments: {
        recipient_id: SecureRandom.uuid,
        message: "recover-once"
      },
      idempotency_key: "delivery:recovery"
    )
    run = PluginJobRun.find_by!(public_id: result.value.fetch("public_id"))
    now = Time.current.change(usec: 0)
    run.update_columns(
      status: "queued",
      scheduled_at: now - 10.minutes,
      enqueued_at: now - 10.minutes,
      recovery_claimed_at: nil
    )
    clear_enqueued_jobs
    outcomes = Queue.new
    ready = Queue.new
    gate = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          gate.pop
          outcomes << Mcweb::Plugins::JobRecovery.call(now:)
        end
      end
    end
    2.times { ready.pop }
    2.times { gate << true }
    threads.each(&:join)
    recovered_counts = 2.times.map { outcomes.pop }

    assert_equal 1, recovered_counts.sum
    assert_equal(
      1,
      enqueued_jobs.count { |job| job.fetch(:job) == PluginOwnedJob }
    )
    assert_predicate run.reload.recovery_claimed_at, :present?
  end

  private

  def register_plugin(&handler)
    directory = @root.join("plugin")
    FileUtils.mkdir_p(directory.join("config"))
    File.write(
      directory.join("config/jobs.yml"),
      YAML.dump(
        "schema_version" => "1",
        "jobs" => {
          "deliver" => {
            "max_attempts" => 3,
            "retry_wait_seconds" => 0,
            "lease_seconds" => 60,
            "arguments" => {
              "$schema" => Mcweb::Plugins::JobContribution::DRAFT_URI,
              "type" => "object",
              "additionalProperties" => false,
              "required" => %w[recipient_id message],
              "properties" => {
                "recipient_id" => { "type" => "string", "format" => "uuid" },
                "message" => { "type" => "string" }
              }
            }
          }
        }
      )
    )
    File.write(
      directory.join("mcweb_plugin.yml"),
      YAML.dump(
        "id" => "acme/jobs",
        "name" => "Jobs",
        "version" => "1.0.0",
        "api_version" => "1",
        "capabilities" => %w[plugin.jobs.read plugin.jobs.enqueue],
        "contributions" => { "jobs" => "config/jobs.yml" }
      )
    )
    manifest = Mcweb::Plugins::Manifest.load_file(directory.join("mcweb_plugin.yml"))
    definition = Mcweb::Plugins.register(manifest) do |plugin|
      plugin.job("deliver", &(handler || ->(*) { }))
    end
    Mcweb::Plugins.boot!
    definition
  end
end
