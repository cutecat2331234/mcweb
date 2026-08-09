# frozen_string_literal: true

# Downstream editions append code-owned registrars here. The catalog invokes
# every registrar exactly once, then freezes the allowlist before it can be
# queried or executed. Registrars must register explicit executors; class names,
# job names, shell commands, and arbitrary constants are never accepted as input.
Rails.application.config.x.operations_manual_task_registrars ||= []
