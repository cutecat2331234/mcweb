# frozen_string_literal: true

require "test_helper"
require "mcweb/plugin_api/v1/host"

class Mcweb::PluginApi::V1::StorageTest < ActiveSupport::TestCase
  setup do
    @storage = build_storage("acme/storage")
    @other_storage = build_storage("other/storage")
  end

  test "put read list overwrite and delete remain inside the plugin namespace" do
    created = @storage.put(
      key: "exports/report.txt",
      data: "first",
      content_type: "text/plain",
      metadata: { purpose: "test" },
      expires_in: 1.hour.to_i
    )
    assert_predicate created, :success?
    assert_equal "exports/report.txt", created.value.fetch("key")
    assert_equal Digest::SHA256.hexdigest("first"), created.value.fetch("checksum_sha256")
    refute created.value.key?("data")

    hidden = @other_storage.find(key: "exports/report.txt")
    assert_predicate hidden, :failure?
    assert_equal "not_found", hidden.code

    read = @storage.read(key: "exports/report.txt")
    assert_predicate read, :success?
    assert_equal "first", Base64.strict_decode64(read.value.fetch("data"))
    assert_equal "base64", read.value.fetch("encoding")

    original_public_id = created.value.fetch("public_id")
    overwritten = @storage.put(
      key: "exports/report.txt",
      data: "second",
      content_type: "text/plain"
    )
    assert_predicate overwritten, :success?
    assert_equal original_public_id, overwritten.value.fetch("public_id")
    assert_equal "second", Base64.strict_decode64(
      @storage.read(key: "exports/report.txt").value.fetch("data")
    )

    listed = @storage.list(prefix: "exports/")
    assert_predicate listed, :success?
    assert_equal [ "exports/report.txt" ], listed.value.map { |item| item.fetch("key") }

    deleted = @storage.delete(key: "exports/report.txt")
    assert_predicate deleted, :success?
    assert_equal true, deleted.value.fetch("deleted")
    assert_equal "not_found", @storage.find(key: "exports/report.txt").code
  end

  test "storage validates traversal size metadata and replacement policy" do
    assert_equal "invalid_key", @storage.put(key: "../secret", data: "x").code
    assert_equal "invalid_key", @storage.put(key: "safe\\secret", data: "x").code
    assert_equal(
      "object_too_large",
      @storage.put(key: "large.bin", data: "x" * (Mcweb::PluginApi::V1::Storage::MAX_OBJECT_BYTES + 1)).code
    )
    assert_equal(
      "metadata_too_large",
      @storage.put(key: "meta.bin", data: "x", metadata: { value: "x" * 40_000 }).code
    )

    assert_predicate @storage.put(key: "once.txt", data: "one"), :success?
    conflict = @storage.put(key: "once.txt", data: "two", overwrite: false)
    assert_predicate conflict, :failure?
    assert_equal "already_exists", conflict.code
  end

  test "expired objects are hidden and maintenance purges their metadata" do
    result = @storage.put(key: "temporary.txt", data: "temporary", expires_in: 60)
    record = PluginStorageObject.find_by!(public_id: result.value.fetch("public_id"))
    record.update_column(:expires_at, 1.minute.ago)

    assert_equal "not_found", @storage.find(key: "temporary.txt").code
    assert_difference -> { PluginStorageObject.count }, -1 do
      ExpirePluginStorageObjectsJob.perform_now
    end
  end

  test "inline reads have a stricter bound than stored objects" do
    data = "x" * (Mcweb::PluginApi::V1::Storage::MAX_READ_BYTES + 1)
    assert_predicate @storage.put(key: "archive.bin", data:), :success?

    result = @storage.read(key: "archive.bin")
    assert_predicate result, :failure?
    assert_equal "object_too_large_to_read", result.code
  end

  private

  def build_storage(plugin_id)
    manifest = Mcweb::Plugins::Manifest.from_hash({
      id: plugin_id,
      name: plugin_id,
      version: "1.0.0",
      api_version: "1",
      capabilities: %w[plugin.storage.read plugin.storage.write]
    })
    Mcweb::PluginApi::V1::Host.new(
      manifest:,
      event_bus: Mcweb::Events
    ).storage
  end
end
