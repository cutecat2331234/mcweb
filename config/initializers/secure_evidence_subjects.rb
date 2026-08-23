# frozen_string_literal: true

require Rails.root.join("lib/mcweb/secure_evidence_subject_registrar_config")
require Rails.root.join("app/services/community/allowed_attachment_types")
require Rails.root.join("app/services/community/secure_evidence_subjects")

Mcweb::SecureEvidenceSubjectRegistrarConfig.initialize!(Rails.application.config.x)
Mcweb::SecureEvidenceSubjectRegistrarConfig.register!(
  Rails.application.config.x,
  Community::SecureEvidenceSubjects::REGISTRAR
)

Rails.application.reloader.to_prepare do
  SecureEvidence::SubjectCatalog.finalize!
end
