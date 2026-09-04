# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Identity
  class DataExportTemporaryStorageTest < ActiveSupport::TestCase
    setup do
      @root = Pathname(Dir.mktmpdir("data-export-temporary-storage"))
      @temporary_files = []
    end

    teardown do
      @temporary_files.each do |file|
        file.close!
      rescue StandardError
        nil
      end
      FileUtils.remove_entry(@root) if @root.exist?
    end

    test "creates private archives only inside the dedicated directory" do
      archive = tracked_archive

      assert_equal @root.expand_path, Pathname(archive.path).dirname
      assert Pathname(archive.path).basename.to_s.start_with?(DataExportTemporaryStorage::FILE_PREFIX)
      assert Pathname(archive.path).basename.to_s.end_with?(DataExportTemporaryStorage::FILE_SUFFIX)
      unless Gem.win_platform?
        assert_equal 0o700, File.stat(@root).mode & 0o777
        assert_equal 0o600, File.stat(archive.path).mode & 0o777
      end
    end

    test "removes only managed files older than the orphan threshold" do
      now = Time.zone.parse("2026-09-04 12:00:00 UTC")
      old_archive = tracked_archive
      recent_archive = tracked_archive
      old_archive.close
      recent_archive.close
      File.utime((now - 7.hours).to_time, (now - 7.hours).to_time, old_archive.path)
      File.utime((now - 1.hour).to_time, (now - 1.hour).to_time, recent_archive.path)
      foreign_file = @root.join("unmanaged.zip")
      foreign_file.binwrite("keep")
      File.utime((now - 7.days).to_time, (now - 7.days).to_time, foreign_file)

      result = DataExportTemporaryStorage.cleanup_orphans!(root: @root, now:)

      assert_equal({ scanned: 2, removed: 1, retained: 1, failed: 0 }, result)
      refute File.exist?(old_archive.path)
      assert File.exist?(recent_archive.path)
      assert foreign_file.exist?
    end

    private

    def tracked_archive
      DataExportTemporaryStorage.create(root: @root).tap do |archive|
        @temporary_files << archive
      end
    end
  end
end
