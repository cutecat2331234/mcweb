# frozen_string_literal: true

require "test_helper"
require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "mcweb/disaster_recovery/backup_retention"

class Mcweb::DisasterRecovery::BackupRetentionTest < ActiveSupport::TestCase
  NOW = Time.utc(2030, 1, 1, 12)

  test "retention removes only expired complete generations beyond the minimum count" do
    Dir.mktmpdir("backup-retention") do |root|
      create_local_backup(root, "old-1", NOW - 100.days)
      create_local_backup(root, "old-2", NOW - 60.days)
      create_local_backup(root, "recent", NOW - 1.day)
      FileUtils.mkdir_p(File.join(root, "incomplete"))
      File.write(File.join(root, "incomplete", "database.dump"), "partial")

      retention = described_class.new(
        root:,
        retention_days: "30",
        retention_count: "1",
        now: NOW
      )

      assert_equal %w[old-2 old-1], retention.prune!
      assert_not Dir.exist?(File.join(root, "old-1"))
      assert_not Dir.exist?(File.join(root, "old-2"))
      assert Dir.exist?(File.join(root, "recent"))
      assert Dir.exist?(File.join(root, "incomplete"))
    end
  end

  test "corrupt complete generation fails closed without deleting it" do
    Dir.mktmpdir("backup-retention") do |root|
      path = create_local_backup(root, "corrupt", NOW - 100.days)
      File.binwrite(File.join(path, "database.dump"), "changed after publication")

      error = assert_raises(described_class::Error) do
        described_class.new(
          root:,
          retention_days: "30",
          retention_count: "1",
          now: NOW
        ).prune!
      end

      assert_equal "backup_generation_integrity_failed", error.code
      assert Dir.exist?(path)
    end
  end

  test "an interrupted staged prune is resumed before evaluating policy" do
    Dir.mktmpdir("backup-retention") do |root|
      path = create_local_backup(root, "staged", NOW - 100.days)
      staged = File.join(root, ".pruning-staged")
      File.rename(path, staged)

      pruned = described_class.new(
        root:,
        retention_days: "30",
        retention_count: "1",
        now: NOW
      ).prune!

      assert_empty pruned
      assert_not Dir.exist?(staged)
    end
  end

  private

  def described_class
    Mcweb::DisasterRecovery::BackupRetention
  end

  def create_local_backup(root, backup_id, created_at)
    path = File.join(root, backup_id)
    FileUtils.mkdir_p(path)
    File.binwrite(File.join(path, "database.dump"), "dump:#{backup_id}")
    manifest = {
      format: "mcweb-backup-v2",
      backup_id:,
      created_at: created_at.iso8601,
      active_storage: {
        mode: "local",
        inventory: "active_storage_files.sha256",
        archive: "active_storage.tar.gz",
        remote_snapshot: nil
      }
    }
    File.binwrite(
      File.join(path, "backup-manifest.json"),
      JSON.pretty_generate(manifest) << "\n"
    )
    checksum_lines = Dir.children(path).sort.map do |name|
      "#{Digest::SHA256.file(File.join(path, name)).hexdigest}  #{name}"
    end
    File.binwrite(File.join(path, "SHA256SUMS"), checksum_lines.join("\n") << "\n")
    path
  end
end
