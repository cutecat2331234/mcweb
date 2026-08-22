# frozen_string_literal: true

require "test_helper"
require "base64"
require "digest"
require "json"
require "tmpdir"
require "mcweb/disaster_recovery/object_archive"

class Mcweb::DisasterRecovery::ObjectArchiveTest < ActiveSupport::TestCase
  FakeBlob = Data.define(:id, :key, :service_name, :byte_size, :checksum, :content) do
    def download
      content.bytes.each_slice(3) { |bytes| yield bytes.pack("C*") }
    end
  end

  class FakeClient
    attr_reader :objects, :put_count, :deleted

    def initialize(objects = {})
      @objects = objects.transform_keys { |key| Array(key) }
      @put_count = 0
      @deleted = []
    end

    def get_object(bucket:, key:)
      content = objects.fetch([ bucket, key ]) do
        raise Aws::S3::Errors::NoSuchKey.new(nil, "missing")
      end
      content.bytes.each_slice(2) { |bytes| yield bytes.pack("C*") }
    end

    def put_object(bucket:, key:, body:, content_length:, metadata:, if_none_match:)
      raise "conditional write required" unless if_none_match == "*"
      raise "unexpected metadata" unless metadata.keys.all? { |name| name.start_with?("mcweb-") }
      raise "fake immutable collision" if objects.key?([ bucket, key ])

      content = body.read
      raise "content length differs" unless content.bytesize == content_length

      objects[[ bucket, key ]] = content
      @put_count += 1
      true
    end

    def delete_object(bucket:, key:)
      objects.delete([ bucket, key ])
      deleted << [ bucket, key ]
      true
    end
  end

  test "snapshot stores independent bytes and emits a secret-free verified record" do
    content = "independent object snapshot\n"
    blob = build_blob(content:)
    client = FakeClient.new
    store = build_store(client:, bucket: "backup-bucket")
    archive = described_class.new(backup_store: store)

    record = archive.snapshot(
      blob:,
      source_bucket: "primary-bucket",
      backup_key: "backups/run-1/objects/blob-key"
    )

    assert_equal content, client.objects.fetch([ "backup-bucket", record.fetch(:snapshot_key) ])
    assert_equal Digest::SHA256.hexdigest(content), record.fetch(:sha256)
    assert_equal content.bytesize, record.fetch(:byte_size)
    assert_equal true, record.fetch(:verified)
    assert_equal 1, client.put_count
    assert_not_includes JSON.generate(record), "secret-access-key"
    assert_not_includes JSON.generate(record), "customer-filename"

    reused = archive.snapshot(
      blob:,
      source_bucket: "primary-bucket",
      backup_key: "backups/run-1/objects/blob-key"
    )
    assert_equal record, reused
    assert_equal 1, client.put_count
  end

  test "verify detects corruption and restore is retryable but refuses collisions" do
    content = "recoverable object\n"
    blob = build_blob(content:)
    backup_client = FakeClient.new
    backup_store = build_store(client: backup_client, bucket: "backup-bucket")
    archive = described_class.new(backup_store:)
    raw_record = archive.snapshot(
      blob:,
      source_bucket: "primary-bucket",
      backup_key: "backups/run-2/objects/blob-key"
    )
    inventory = write_inventory(raw_record)
    target_client = FakeClient.new
    target_store = build_store(client: target_client, bucket: "restore-bucket")

    assert_equal 1, archive.verify(inventory)
    assert_equal 1, archive.restore(inventory, target_store:)
    assert_equal content, target_client.objects.fetch([ "restore-bucket", "blob-key" ])
    assert_equal 1, target_client.put_count
    assert_equal 1, archive.restore(inventory, target_store:)
    assert_equal 1, target_client.put_count

    target_client.objects[[ "restore-bucket", "blob-key" ]] = "different"
    error = assert_raises(described_class::Error) do
      archive.restore(inventory, target_store:)
    end
    assert_equal "immutable_object_collision", error.code

    backup_client.objects[[ "backup-bucket", "backups/run-2/objects/blob-key" ]] = "corrupt"
    error = assert_raises(described_class::Error) { archive.verify(inventory) }
    assert_equal "snapshot_integrity_mismatch", error.code
  end

  test "restore target must be isolated from source and backup buckets" do
    record = {
      format: described_class::INVENTORY_FORMAT,
      id: 1,
      service_name: "private_s3",
      source_bucket: "primary-bucket",
      source_key: "blob-key",
      snapshot_bucket: "backup-bucket",
      snapshot_key: "backups/run-3/objects/blob-key",
      byte_size: 0,
      sha256: Digest::SHA256.hexdigest(""),
      active_storage_checksum: nil,
      verified: true
    }
    inventory = write_inventory(record)
    archive = described_class.new(
      backup_store: build_store(client: FakeClient.new, bucket: "backup-bucket")
    )

    [ "primary-bucket", "backup-bucket" ].each do |bucket|
      error = assert_raises(described_class::Error) do
        archive.restore(
          inventory,
          target_store: build_store(client: FakeClient.new, bucket:)
        )
      end
      assert_equal "restore_bucket_not_isolated", error.code
    end
  end

  test "remote pruning is prefix-bound and idempotent after interruption" do
    content = "expired snapshot\n"
    blob = build_blob(content:)
    client = FakeClient.new
    store = build_store(client:, bucket: "backup-bucket")
    archive = described_class.new(backup_store: store)
    record = archive.snapshot(
      blob:,
      source_bucket: "primary-bucket",
      backup_key: "backups/run-5/objects/blob-key"
    )
    inventory = write_inventory(record)

    error = assert_raises(described_class::Error) do
      archive.prune(inventory, expected_prefix: "backups/different/objects")
    end
    assert_equal "snapshot_prune_scope_invalid", error.code
    assert client.objects.key?([ "backup-bucket", "backups/run-5/objects/blob-key" ])

    assert_equal 1, archive.prune(inventory, expected_prefix: "backups/run-5/objects")
    assert_equal 1, archive.prune(inventory, expected_prefix: "backups/run-5/objects")
    assert_equal [ [ "backup-bucket", "backups/run-5/objects/blob-key" ] ], client.deleted
  end

  test "inventory rejects duplicate and unsafe object locators" do
    Dir.mktmpdir("object-archive-inventory") do |directory|
      path = File.join(directory, "inventory.ndjson")
      record = {
        format: described_class::INVENTORY_FORMAT,
        id: 1,
        service_name: "private_s3",
        source_bucket: "primary-bucket",
        source_key: "../unsafe",
        snapshot_bucket: "backup-bucket",
        snapshot_key: "backups/run-4/objects/blob-key",
        byte_size: 1,
        sha256: Digest::SHA256.hexdigest("x"),
        active_storage_checksum: nil,
        verified: true
      }
      File.write(path, JSON.generate(record) << "\n")

      error = assert_raises(described_class::Error) do
        described_class::Inventory.load(path)
      end
      assert_equal "object_inventory_invalid", error.code
    end
  end

  private

  def described_class
    Mcweb::DisasterRecovery::ObjectArchive
  end

  def build_blob(content:)
    FakeBlob.new(
      id: 1,
      key: "blob-key",
      service_name: "private_s3",
      byte_size: content.bytesize,
      checksum: Base64.strict_encode64(Digest::MD5.digest(content)),
      content:
    )
  end

  def build_store(client:, bucket:)
    described_class::Store.new(client:, bucket:)
  end

  def write_inventory(record)
    Dir.mktmpdir("object-archive-record") do |directory|
      path = File.join(directory, "inventory.ndjson")
      File.write(path, JSON.generate(record) << "\n")
      return described_class::Inventory.load(path)
    end
  end
end
