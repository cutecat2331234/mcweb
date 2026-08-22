# frozen_string_literal: true

module SecureEvidence
  class SubjectRegistry
    HARD_MAX_FILE_BYTES = 10.megabytes
    HARD_MAX_FILES = 20
    HARD_MAX_TOTAL_BYTES = 100.megabytes
    KEY_PATTERN = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/
    MODEL_NAME_PATTERN = /\A[A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*\z/

    Entry = Data.define(
      :key,
      :model_name,
      :resolver,
      :upload_authorizer,
      :download_authorizer,
      :discard_authorizer,
      :retention,
      :max_files,
      :max_file_bytes,
      :max_total_bytes,
      :allowed_extensions
    )

    def initialize
      @entries = {}
      @model_names = {}
      @frozen = false
    end

    def register(
      key:,
      model_name:,
      resolver:,
      upload_authorizer:,
      download_authorizer:,
      retention:,
      max_files:,
      max_file_bytes:,
      max_total_bytes:,
      allowed_extensions:,
      discard_authorizer: nil
    )
      raise FrozenError, "secure_evidence_subject_registry_frozen" if frozen?

      normalized_key = key.to_s
      normalized_model_name = model_name.to_s
      validate_identity!(normalized_key, normalized_model_name)
      validate_callable!(:resolver, resolver)
      validate_callable!(:upload_authorizer, upload_authorizer)
      validate_callable!(:download_authorizer, download_authorizer)
      validate_optional_callable!(:discard_authorizer, discard_authorizer)
      validate_callable!(:retention, retention)

      limits = validate_limits!(
        max_files:,
        max_file_bytes:,
        max_total_bytes:
      )
      extensions = validate_extensions!(allowed_extensions)

      entry = Entry.new(
        key: normalized_key.freeze,
        model_name: normalized_model_name.freeze,
        resolver:,
        upload_authorizer:,
        download_authorizer:,
        discard_authorizer:,
        retention:,
        **limits,
        allowed_extensions: extensions
      ).freeze
      @entries[normalized_key] = entry
      @model_names[normalized_model_name] = normalized_key
      entry
    end

    def entry_for_key(key)
      @entries[key.to_s]
    end

    def entries
      @entries.values.freeze
    end

    def freeze!
      @entries.freeze
      @model_names.freeze
      @frozen = true
      self
    end

    def frozen?
      @frozen
    end

    private

    def validate_identity!(key, model_name)
      raise ArgumentError, "secure_evidence_subject_key_invalid" unless key.match?(KEY_PATTERN)
      raise ArgumentError, "secure_evidence_subject_model_invalid" unless model_name.match?(MODEL_NAME_PATTERN)
      raise ArgumentError, "secure_evidence_subject_duplicate" if @entries.key?(key)
      raise ArgumentError, "secure_evidence_subject_model_duplicate" if @model_names.key?(model_name)
    end

    def validate_callable!(name, callable)
      return if callable.respond_to?(:call)

      raise ArgumentError, "secure_evidence_subject_#{name}_invalid"
    end

    def validate_optional_callable!(name, callable)
      return if callable.nil?

      validate_callable!(name, callable)
    end

    def validate_limits!(max_files:, max_file_bytes:, max_total_bytes:)
      normalized = {
        max_files: Integer(max_files, exception: false),
        max_file_bytes: Integer(max_file_bytes, exception: false),
        max_total_bytes: Integer(max_total_bytes, exception: false)
      }
      ranges = {
        max_files: 1..HARD_MAX_FILES,
        max_file_bytes: 1..HARD_MAX_FILE_BYTES,
        max_total_bytes: 1..HARD_MAX_TOTAL_BYTES
      }
      normalized.each do |name, value|
        raise ArgumentError, "secure_evidence_subject_#{name}_invalid" unless ranges.fetch(name).cover?(value)
      end
      if normalized.fetch(:max_file_bytes) > normalized.fetch(:max_total_bytes)
        raise ArgumentError, "secure_evidence_subject_total_bytes_invalid"
      end

      normalized.freeze
    end

    def validate_extensions!(extensions)
      normalized = Array(extensions).map do |extension|
        extension.to_s.strip.downcase.delete_prefix(".")
      end.reject(&:blank?).uniq.sort
      supported = Community::AllowedAttachmentTypes::DEFAULT_EXTENSIONS
      if normalized.empty? || (normalized - supported).any?
        raise ArgumentError, "secure_evidence_subject_extensions_invalid"
      end

      normalized.freeze
    end
  end
end
