# frozen_string_literal: true

require "aws-sdk-s3"
require "base64"
require "digest"
require "json"
require "tempfile"
require "uri"

module Mcweb
  module DisasterRecovery
    class ObjectArchive
      INVENTORY_FORMAT = "mcweb-object-snapshot-v1"
      KEY_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._\/-]*\z/
      SHA256_PATTERN = /\A[0-9a-f]{64}\z/

      DigestResult = Data.define(:byte_size, :sha256)

      class Error < StandardError
        attr_reader :code

        def initialize(code)
          @code = code
          super(code)
        end
      end

      class Store
        attr_reader :bucket

        def self.from_environment(prefix, environment: ENV)
          bucket = required_value(environment, "#{prefix}_BUCKET", "object_store_bucket_missing")
          region = required_value(environment, "#{prefix}_REGION", "object_store_region_missing")
          validate_bucket!(bucket)

          access_key = environment["#{prefix}_ACCESS_KEY_ID"].to_s
          secret_key = environment["#{prefix}_SECRET_ACCESS_KEY"].to_s
          session_token = environment["#{prefix}_SESSION_TOKEN"].to_s
          unless access_key.empty? == secret_key.empty?
            raise Error, "object_store_credentials_incomplete"
          end
          if access_key.empty? && !session_token.empty?
            raise Error, "object_store_credentials_incomplete"
          end

          options = {
            region:,
            force_path_style: boolean_value(environment["#{prefix}_FORCE_PATH_STYLE"])
          }
          endpoint = environment["#{prefix}_ENDPOINT"].to_s
          options[:endpoint] = validate_endpoint!(endpoint) unless endpoint.empty?
          unless access_key.empty?
            options[:access_key_id] = access_key
            options[:secret_access_key] = secret_key
            options[:session_token] = session_token unless session_token.empty?
          end

          new(client: Aws::S3::Client.new(**options), bucket:)
        end

        def self.required_value(environment, name, code)
          value = environment[name].to_s
          raise Error, code if value.empty? || value.match?(/[\r\n]/)

          value
        end
        private_class_method :required_value

        def self.validate_bucket!(bucket)
          return if bucket.bytesize.between?(1, 255) && bucket.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/)

          raise Error, "object_store_bucket_invalid"
        end
        private_class_method :validate_bucket!

        def self.validate_endpoint!(endpoint)
          uri = URI.parse(endpoint)
          valid = uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo && !uri.query && !uri.fragment &&
            [ "", "/" ].include?(uri.path.to_s)
          raise Error, "object_store_endpoint_invalid" unless valid

          endpoint
        rescue URI::InvalidURIError
          raise Error, "object_store_endpoint_invalid"
        end
        private_class_method :validate_endpoint!

        def self.boolean_value(value)
          %w[1 true yes on].include?(value.to_s.downcase)
        end
        private_class_method :boolean_value

        def initialize(client:, bucket:)
          @client = client
          @bucket = bucket
        end

        def digest(key)
          validate_key!(key)
          digest = Digest::SHA256.new
          byte_size = 0
          @client.get_object(bucket:, key:) do |chunk|
            digest.update(chunk)
            byte_size += chunk.bytesize
          end
          DigestResult.new(byte_size:, sha256: digest.hexdigest)
        rescue Aws::S3::Errors::NoSuchKey
          nil
        rescue Aws::S3::Errors::ServiceError => error
          return nil if http_status(error) == 404

          raise
        end

        def download_to(key, output)
          validate_key!(key)
          digest = Digest::SHA256.new
          byte_size = 0
          @client.get_object(bucket:, key:) do |chunk|
            output.write(chunk)
            digest.update(chunk)
            byte_size += chunk.bytesize
          end
          output.flush
          DigestResult.new(byte_size:, sha256: digest.hexdigest)
        rescue Aws::S3::Errors::NoSuchKey
          raise Error, "snapshot_object_missing"
        rescue Aws::S3::Errors::ServiceError => error
          raise Error, "snapshot_object_missing" if http_status(error) == 404

          raise
        end

        def publish_immutable(key, input, expected:, metadata:)
          validate_key!(key)
          existing = digest(key)
          return ensure_matching!(existing, expected) if existing

          input.rewind
          @client.put_object(
            bucket:,
            key:,
            body: input,
            content_length: expected.byte_size,
            metadata:,
            if_none_match: "*"
          )
          ensure_matching!(digest(key), expected)
        rescue Aws::S3::Errors::ServiceError => error
          raise unless http_status(error) == 412

          ensure_matching!(digest(key), expected)
        end

        def delete_verified(key, expected:)
          actual = digest(key)
          return unless actual

          ensure_matching!(actual, expected)
          @client.delete_object(bucket:, key:)
        end

        private

        def ensure_matching!(actual, expected)
          raise Error, "snapshot_object_missing" unless actual
          unless actual.byte_size == expected.byte_size && actual.sha256 == expected.sha256
            raise Error, "immutable_object_collision"
          end

          actual
        end

        def validate_key!(key)
          value = key.to_s
          segments = value.split("/")
          valid = value.bytesize.between?(1, 1024) && value.match?(KEY_PATTERN) &&
            segments.none? { |segment| segment.empty? || [ ".", ".." ].include?(segment) }
          raise Error, "object_store_key_invalid" unless valid
        end

        def http_status(error)
          error.context&.http_response&.status_code
        end
      end

      class Inventory
        include Enumerable

        def self.load(path)
          records = []
          source_keys = {}
          snapshot_keys = {}

          File.foreach(path) do |line|
            next if line.strip.empty?

            record = validate_record!(JSON.parse(line))
            raise Error, "object_inventory_duplicate_source" if source_keys[record.fetch("source_key")]
            raise Error, "object_inventory_duplicate_snapshot" if snapshot_keys[record.fetch("snapshot_key")]

            source_keys[record.fetch("source_key")] = true
            snapshot_keys[record.fetch("snapshot_key")] = true
            records << record.freeze
          rescue JSON::ParserError
            raise Error, "object_inventory_invalid"
          end

          new(records.freeze)
        rescue Errno::ENOENT, Errno::EACCES
          raise Error, "object_inventory_unreadable"
        end

        def self.validate_record!(record)
          valid = record.is_a?(Hash) &&
            record["format"] == INVENTORY_FORMAT &&
            record["id"].is_a?(Integer) && record["id"].positive? &&
            record["service_name"] == "private_s3" &&
            valid_bucket?(record["source_bucket"]) &&
            valid_key?(record["source_key"]) &&
            valid_bucket?(record["snapshot_bucket"]) &&
            valid_key?(record["snapshot_key"]) &&
            record["byte_size"].is_a?(Integer) && record["byte_size"] >= 0 &&
            record["sha256"].is_a?(String) && record["sha256"].match?(SHA256_PATTERN) &&
            (record["active_storage_checksum"].nil? || record["active_storage_checksum"].is_a?(String)) &&
            record["verified"] == true
          raise Error, "object_inventory_invalid" unless valid

          record
        end
        private_class_method :validate_record!

        def self.valid_bucket?(value)
          value.is_a?(String) && value.bytesize.between?(1, 255) &&
            value.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/)
        end
        private_class_method :valid_bucket?

        def self.valid_key?(value)
          return false unless value.is_a?(String) && value.bytesize.between?(1, 1024) && value.match?(KEY_PATTERN)

          value.split("/").none? { |segment| segment.empty? || [ ".", ".." ].include?(segment) }
        end
        private_class_method :valid_key?

        def initialize(records)
          @records = records
        end

        def each(&)
          @records.each(&)
        end

        def size
          @records.size
        end
      end

      def initialize(backup_store:)
        @backup_store = backup_store
      end

      def backup_bucket
        @backup_store.bucket
      end

      def snapshot(blob:, source_bucket:, backup_key:)
        raise Error, "backup_bucket_matches_source" if @backup_store.bucket == source_bucket

        with_downloaded_blob(blob) do |temporary, expected|
          @backup_store.publish_immutable(
            backup_key,
            temporary,
            expected:,
            metadata: {
              "mcweb-sha256" => expected.sha256,
              "mcweb-source-service" => "private_s3"
            }
          )
          {
            format: INVENTORY_FORMAT,
            id: blob.id,
            service_name: blob.service_name,
            source_bucket:,
            source_key: blob.key,
            snapshot_bucket: @backup_store.bucket,
            snapshot_key: backup_key,
            byte_size: expected.byte_size,
            sha256: expected.sha256,
            active_storage_checksum: blob.checksum,
            verified: true
          }
        end
      end

      def verify(inventory)
        inventory.each do |record|
          verify_record_store!(record, @backup_store)
        end
        inventory.size
      end

      def restore(inventory, target_store:, source_bucket: nil)
        sources = inventory.map { |record| record.fetch("source_bucket") }
        sources << source_bucket if source_bucket
        if target_store.bucket == @backup_store.bucket || sources.include?(target_store.bucket)
          raise Error, "restore_bucket_not_isolated"
        end

        inventory.each do |record|
          verify_record_store!(record, @backup_store)
          expected = expected_digest(record)
          existing = target_store.digest(record.fetch("source_key"))
          if existing
            unless existing.byte_size == expected.byte_size && existing.sha256 == expected.sha256
              raise Error, "immutable_object_collision"
            end
            next
          end

          Tempfile.create([ "mcweb-object-restore-", ".bin" ]) do |temporary|
            temporary.binmode
            downloaded = @backup_store.download_to(record.fetch("snapshot_key"), temporary)
            unless downloaded.byte_size == expected.byte_size && downloaded.sha256 == expected.sha256
              raise Error, "snapshot_integrity_mismatch"
            end

            target_store.publish_immutable(
              record.fetch("source_key"),
              temporary,
              expected:,
              metadata: { "mcweb-restored-sha256" => expected.sha256 }
            )
          end
        end
        inventory.size
      end

      def prune(inventory, expected_prefix:)
        prefix = "#{expected_prefix}/"
        inventory.each do |record|
          unless record.fetch("snapshot_key").start_with?(prefix)
            raise Error, "snapshot_prune_scope_invalid"
          end
          unless record.fetch("snapshot_bucket") == @backup_store.bucket
            raise Error, "backup_store_mismatch"
          end

          @backup_store.delete_verified(record.fetch("snapshot_key"), expected: expected_digest(record))
        end
        inventory.size
      end

      private

      def with_downloaded_blob(blob)
        raise Error, "object_service_mismatch" unless blob.service_name == "private_s3"

        Tempfile.create([ "mcweb-object-snapshot-", ".bin" ]) do |temporary|
          temporary.binmode
          sha256 = Digest::SHA256.new
          md5 = Digest::MD5.new
          byte_size = 0
          blob.download do |chunk|
            temporary.write(chunk)
            sha256.update(chunk)
            md5.update(chunk)
            byte_size += chunk.bytesize
          end
          temporary.flush
          expected = DigestResult.new(byte_size:, sha256: sha256.hexdigest)
          raise Error, "source_object_size_mismatch" unless byte_size == blob.byte_size

          if blob.checksum && !blob.checksum.empty? && Base64.strict_encode64(md5.digest) != blob.checksum
            raise Error, "source_object_checksum_mismatch"
          end
          yield temporary, expected
        end
      end

      def verify_record_store!(record, store)
        raise Error, "backup_store_mismatch" unless record.fetch("snapshot_bucket") == store.bucket

        actual = store.digest(record.fetch("snapshot_key"))
        expected = expected_digest(record)
        unless actual && actual.byte_size == expected.byte_size && actual.sha256 == expected.sha256
          raise Error, "snapshot_integrity_mismatch"
        end

        actual
      end

      def expected_digest(record)
        DigestResult.new(
          byte_size: record.fetch("byte_size"),
          sha256: record.fetch("sha256")
        )
      end
    end
  end
end
