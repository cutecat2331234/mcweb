# frozen_string_literal: true

require "test_helper"

module SecureEvidence
  class SubjectRegistryTest < ActiveSupport::TestCase
    test "validates contracts bounds uniqueness and freeze boundary" do
      registry = SubjectRegistry.new
      entry = registry.register(**valid_registration)

      assert_equal "test.evidence_case", entry.key
      assert_equal %w[pdf txt], entry.allowed_extensions
      assert_raises(ArgumentError) { registry.register(**valid_registration) }
      assert_raises(ArgumentError) do
        registry.register(**valid_registration.merge(key: "invalid"))
      end
      assert_raises(ArgumentError) do
        registry.register(**valid_registration.merge(model_name: "bad model"))
      end
      assert_raises(ArgumentError) do
        registry.register(**valid_registration.merge(max_file_bytes: 11.megabytes))
      end
      assert_raises(ArgumentError) do
        registry.register(**valid_registration.merge(allowed_extensions: %w[exe]))
      end

      registry.freeze!
      assert_predicate registry, :frozen?
      assert_raises(FrozenError) do
        registry.register(**valid_registration.merge(key: "test.other_case", model_name: "Role"))
      end
    end

    test "boot catalog is frozen even when CE has no product subjects" do
      assert SubjectCatalog.registry_frozen?
      assert_kind_of Array, SubjectCatalog.entries
    end

    test "downstream registrar config accepts callables once and freezes at catalog boundary" do
      custom_config = Rails::Application::Configuration::Custom.new
      registrar = ->(_registry) { }

      Mcweb::SecureEvidenceSubjectRegistrarConfig.initialize!(custom_config)
      appended = Mcweb::SecureEvidenceSubjectRegistrarConfig.register!(
        custom_config,
        registrar
      )

      assert_same registrar, appended
      assert_raises(ArgumentError) do
        Mcweb::SecureEvidenceSubjectRegistrarConfig.register!(custom_config, registrar)
      end
      configured = Mcweb::SecureEvidenceSubjectRegistrarConfig.freeze_and_fetch!(custom_config)
      assert_equal [ registrar ], configured
      assert_predicate configured, :frozen?
      assert_raises(FrozenError) do
        Mcweb::SecureEvidenceSubjectRegistrarConfig.register!(
          custom_config,
          ->(_registry) { }
        )
      end
    end

    private

    def valid_registration
      {
        key: "test.evidence_case",
        model_name: "User",
        resolver: ->(public_id:) { User.find_by(public_id:) },
        upload_authorizer: ->(actor:, subject:) { actor == subject },
        download_authorizer: ->(actor:, subject:, attachment:) {
          actor == subject && attachment.subject_id == subject.id
        },
        retention: ->(subject:, attached_at:) { attached_at + 30.days if subject.persisted? },
        max_files: 4,
        max_file_bytes: 1.megabyte,
        max_total_bytes: 4.megabytes,
        allowed_extensions: %w[txt pdf]
      }
    end
  end
end
