# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "tempfile"
require_relative "normalizer"
require_relative "result"

module Mcweb
  module PluginApi
    module V1
      class Storage
        READ_CAPABILITY = "plugin.storage.read"
        WRITE_CAPABILITY = "plugin.storage.write"
        MAX_OBJECT_BYTES = 25.megabytes
        MAX_READ_BYTES = 2.megabytes
        MAX_METADATA_BYTES = 32_768
        MAX_EXPIRY_SECONDS = 1.year.to_i
        MAX_LIMIT = 100
        CONTENT_TYPE_PATTERN = /\A[a-z0-9][a-z0-9!#$&^_.+-]*\/[a-z0-9][a-z0-9!#$&^_.+-]*\z/i

        def initialize(plugin_id:, capability_auditor: nil)
          @plugin_id = plugin_id
          @capability_auditor = capability_auditor
          freeze
        end

        def put(
          key:,
          data:,
          content_type: "application/octet-stream",
          metadata: {},
          expires_in: nil,
          overwrite: true
        )
          audit(WRITE_CAPABILITY)
          key, failure = normalize_key(key)
          return failure if failure
          unless data.is_a?(String)
            return Result.failure(code: "invalid_argument", error: "data must be a string of bytes")
          end
          bytes = data.b
          if bytes.bytesize > MAX_OBJECT_BYTES
            return Result.failure(
              code: "object_too_large",
              error: "object exceeds #{MAX_OBJECT_BYTES} bytes"
            )
          end
          content_type = content_type.to_s.downcase
          unless content_type.length <= 255 && content_type.match?(CONTENT_TYPE_PATTERN)
            return Result.failure(code: "invalid_argument", error: "content_type is invalid")
          end
          metadata, failure = normalize_metadata(metadata)
          return failure if failure
          expires_at, failure = normalize_expiry(expires_in)
          return failure if failure

          record = nil
          Tempfile.create([ "mcweb-plugin-storage", File.extname(key) ]) do |file|
            file.binmode
            file.write(bytes)
            file.flush
            file.rewind

            PluginStorageObject.transaction do
              record = PluginStorageObject.owned_by(@plugin_id).lock.find_by(key:)
              if record && !overwrite
                return Result.failure(code: "already_exists", error: "storage object already exists")
              end
              record ||= PluginStorageObject.new(owner_plugin_id: @plugin_id, key:)
              record.assign_attributes(
                content_type:,
                byte_size: bytes.bytesize,
                checksum_sha256: Digest::SHA256.hexdigest(bytes),
                metadata:,
                expires_at:
              )
              record.save!
              record.file.attach(
                io: file,
                filename: File.basename(key),
                content_type:,
                identify: false
              )
            end
          end

          Result.success(snapshot(record.reload))
        rescue ActiveRecord::RecordNotUnique
          Result.failure(code: "already_exists", error: "storage object already exists")
        rescue ActiveRecord::RecordInvalid => e
          Result.failure(
            code: "invalid_argument",
            error: "storage object is invalid",
            errors: e.record.errors.to_hash
          )
        rescue StandardError
          Result.failure(code: "host_error", error: "plugin storage operation failed")
        end

        def find(key:)
          audit(READ_CAPABILITY)
          key, failure = normalize_key(key)
          return failure if failure
          record = available_scope.find_by(key:)
          return not_found unless record

          Result.success(snapshot(record))
        rescue StandardError
          Result.failure(code: "host_error", error: "plugin storage operation failed")
        end

        def list(prefix: nil, limit: 50)
          audit(READ_CAPABILITY)
          limit = Integer(limit, exception: false)
          unless limit&.between?(1, MAX_LIMIT)
            return Result.failure(
              code: "invalid_argument",
              error: "limit must be between 1 and #{MAX_LIMIT}"
            )
          end

          relation = available_scope.order(key: :asc, id: :asc)
          if prefix.present?
            prefix = prefix.to_s
            unless prefix.bytesize <= 512 && !prefix.include?("\\") && !prefix.split("/").include?("..")
              return Result.failure(code: "invalid_argument", error: "prefix is invalid")
            end
            escaped = ActiveRecord::Base.sanitize_sql_like(prefix)
            relation = relation.where("key LIKE ?", "#{escaped}%")
          end
          Result.success(relation.limit(limit).map { |record| snapshot(record) })
        rescue StandardError
          Result.failure(code: "host_error", error: "plugin storage operation failed")
        end

        def read(key:)
          audit(READ_CAPABILITY)
          key, failure = normalize_key(key)
          return failure if failure
          record = available_scope.find_by(key:)
          return not_found unless record&.file&.attached?
          if record.byte_size > MAX_READ_BYTES
            return Result.failure(
              code: "object_too_large_to_read",
              error: "object exceeds the inline read limit"
            )
          end

          bytes = record.file.download
          unless bytes.bytesize == record.byte_size &&
              Digest::SHA256.hexdigest(bytes) == record.checksum_sha256
            return Result.failure(code: "integrity_error", error: "storage object integrity check failed")
          end

          Result.success(
            snapshot(record).merge(
              encoding: "base64",
              data: Base64.strict_encode64(bytes)
            ).freeze
          )
        rescue ActiveStorage::FileNotFoundError
          not_found
        rescue StandardError
          Result.failure(code: "host_error", error: "plugin storage operation failed")
        end

        def delete(key:)
          audit(WRITE_CAPABILITY)
          key, failure = normalize_key(key)
          return failure if failure
          record = PluginStorageObject.owned_by(@plugin_id).find_by(key:)
          return not_found unless record

          deleted = snapshot(record).merge(deleted: true, deleted_at: Time.current.iso8601(6)).freeze
          record.destroy!
          Result.success(deleted)
        rescue StandardError
          Result.failure(code: "host_error", error: "plugin storage operation failed")
        end

        private

        def available_scope
          PluginStorageObject.owned_by(@plugin_id).available
        end

        def normalize_key(value)
          key = value.to_s
          unless key.length.between?(1, 512) &&
              key.match?(PluginStorageObject::KEY_PATTERN) &&
              !key.include?("\\") &&
              !key.split("/").include?("..")
            return [ nil, Result.failure(code: "invalid_key", error: "storage key is invalid") ]
          end

          [ key, nil ]
        end

        def normalize_metadata(value)
          unless value.is_a?(Hash)
            return [ nil, Result.failure(code: "invalid_argument", error: "metadata must be a mapping") ]
          end
          json = JSON.generate(value)
          if json.bytesize > MAX_METADATA_BYTES
            return [ nil, Result.failure(code: "metadata_too_large", error: "metadata is too large") ]
          end

          [ JSON.parse(json), nil ]
        rescue JSON::GeneratorError, EncodingError
          [ nil, Result.failure(code: "invalid_argument", error: "metadata must be JSON compatible") ]
        end

        def normalize_expiry(value)
          return [ nil, nil ] if value.nil?

          seconds = Integer(value, exception: false)
          unless seconds&.between?(1, MAX_EXPIRY_SECONDS)
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "expires_in must be between 1 and #{MAX_EXPIRY_SECONDS} seconds"
            ) ]
          end

          [ Time.current + seconds, nil ]
        end

        def snapshot(record)
          {
            schema_version: "1",
            public_id: record.public_id,
            plugin_id: record.owner_plugin_id,
            key: record.key,
            content_type: record.content_type,
            byte_size: record.byte_size,
            checksum_sha256: record.checksum_sha256,
            metadata: Normalizer.call(record.metadata),
            expires_at: record.expires_at&.iso8601(6),
            created_at: record.created_at&.iso8601(6),
            updated_at: record.updated_at&.iso8601(6)
          }.freeze
        end

        def not_found
          Result.failure(code: "not_found", error: "storage object not found")
        end

        def audit(capability)
          @capability_auditor&.call(capability)
        end
      end
    end
  end
end
