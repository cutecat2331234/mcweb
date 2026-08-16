# frozen_string_literal: true

require Rails.root.join("lib/mcweb/operations_metrics_registrar_config")

# Downstream editions may append code-owned metric registrars from later
# initializers. The catalog freezes their definitions before runtime
# instrumentation can record a sample. Development reloads may rebuild the
# same catalog only from the already-frozen registrar list.
Mcweb::OperationsMetricsRegistrarConfig.initialize!(Rails.application.config.x)

Rails.application.reloader.to_prepare do
  Operations::Metrics::Catalog.finalize!
end

Rails.application.config.after_initialize do
  Operations::Metrics::Catalog.finalize!
  Operations::Metrics::Instrumentation.install! unless Rails.env.test?
end
