# frozen_string_literal: true

# Downstream editions may register code-owned handlers during initialization.
# The catalog is finalized after every initializer has run. Stored intent data
# can never select a Ruby constant, executor, or queue that was not registered
# before this boot boundary.
require Rails.root.join("lib/mcweb/operations_durable_enqueue_registrar_config")

Mcweb::OperationsDurableEnqueueRegistrarConfig.initialize!(Rails.application.config.x)

Rails.application.reloader.to_prepare do
  Operations::DurableEnqueueCatalog.finalize!
end
