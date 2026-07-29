class ApplicationJob < ActiveJob::Base
  QUEUE_NAMES = {
    default: "default",
    mailers: "mailers",
    payments: "payments",
    minecraft: "minecraft",
    maintenance: "maintenance",
    plugins: "plugins",
    website: "website"
  }.freeze

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  before_perform :reconcile_plugin_runtime_generation

  private

  def reconcile_plugin_runtime_generation
    return unless defined?(Mcweb::Plugins::GenerationCoordinator)

    Mcweb::Plugins.generation_coordinator.reconcile_current_process!(process_kind: "worker")
  rescue StandardError => e
    Rails.logger.warn(
      "[mcweb.plugins] worker generation reconciliation skipped: #{e.class}: #{e.message}"
    )
  end
end
