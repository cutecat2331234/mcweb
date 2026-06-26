# frozen_string_literal: true

require "mcweb/phrase_backend"

# Chain a DB-backed override backend in front of the default I18n backend, so
# admin "phrases" win over the YAML translations and missing overrides fall
# through unchanged.
Rails.application.config.to_prepare do
  unless I18n.backend.is_a?(I18n::Backend::Chain)
    I18n.backend = I18n::Backend::Chain.new(Mcweb::PhraseBackend.new, I18n.backend)
  end
end
