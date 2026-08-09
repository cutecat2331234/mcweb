# frozen_string_literal: true

# Downstream initializers add code-owned registrars through
# Mcweb::OperationsManualTaskRegistrarConfig.register!. The catalog invokes every
# registrar exactly once, then freezes the allowlist before it can be queried or
# executed. Registrars must register explicit executors; class names, job names,
# shell commands, and arbitrary constants are never accepted as input.
require Rails.root.join("lib/mcweb/operations_manual_task_registrar_config")

Mcweb::OperationsManualTaskRegistrarConfig.initialize!(Rails.application.config.x)
