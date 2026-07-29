# frozen_string_literal: true

require "json"
require "pathname"
require "time"

module Operations
  class DeveloperWorkbenchSnapshot
    CAPTURE_DIRECTORIES = {
      mail: "tmp/developer-mode/mails",
      webhooks: "tmp/developer-mode/webhooks",
      webPush: "tmp/developer-mode/web-push"
    }.freeze
    MAX_CAPTURE_FILES = 2_000
    MAX_CAPTURE_ENTRIES = 8
    MAX_CAPTURE_TAIL_BYTES = 256.kilobytes
    MAX_CAPTURE_LINE_BYTES = 32.kilobytes
    UUID_PATTERN =
      /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
    HTTP_METHODS = %w[DELETE GET HEAD OPTIONS PATCH POST PUT].freeze
    SAFE_TOKEN_PATTERN = /\A[a-z0-9_.:-]{1,64}\z/i

    class << self
      def call(root: Rails.root, capture_kind: "mail", capture_page: 1)
        new(root: root).call(
          capture_kind: capture_kind,
          capture_page: capture_page
        )
      end
    end

    def initialize(root:)
      @root = Pathname(root).expand_path
    end

    def call(capture_kind: "mail", capture_page: 1)
      settings = Mcweb::DeveloperMode.settings

      {
        profile: settings.profile.to_s,
        productionEnvironment: Rails.env.production?,
        autoLoginConfigured: settings.auto_login_user.present?,
        automaticRegistration:
          Mcweb::SidekiqCronSchedule.automatic_registration_enabled?(
            settings: settings
          ),
        configuration: {
          security: active_configuration(settings.security),
          integrations: active_configuration(settings.integrations),
          runtime: active_configuration(settings.runtime)
        },
        captures: {
          mail: capture_summary(:mail),
          webhooks: capture_summary(:webhooks),
          webPush: capture_summary(:webPush)
        },
        captureBrowser: capture_browser(
          kind: capture_kind,
          page: capture_page
        ),
        personas: persona_summary,
        scenarios: {
          seeds: Operations::DeveloperScenarioSeeder::SCENARIOS,
          attachmentStates: Operations::DeveloperUploadScenario::SCENARIOS
        },
        manualTasks: Operations::DeveloperTaskRunner::TASKS.keys,
        diagnostics: diagnostic_summary(settings),
        minecraft: minecraft_summary
      }
    end

    private

    def active_configuration(values)
      values.filter_map do |key, value|
        next if value.nil? || value == :inherit

        {
          key: key.to_s,
          value: value.to_s
        }
      end
    end

    def capture_summary(kind)
      relative_directory = CAPTURE_DIRECTORIES.fetch(kind)
      directory = safe_capture_directory(relative_directory)
      return empty_capture_summary(relative_directory) unless directory

      files, truncated = capture_files(directory)
      entries =
        if kind == :mail
          mail_entries(files)
        else
          jsonl_entries(files, kind)
        end

      {
        relativeDirectory: relative_directory,
        exists: true,
        fileCount: files.length,
        totalBytes: files.sum { |path| safe_file_size(path) },
        truncated: truncated,
        latestEntries: entries
      }
    rescue Errno::EACCES, Errno::ENOENT, IOError, SystemCallError
      empty_capture_summary(relative_directory)
    end

    def empty_capture_summary(relative_directory)
      {
        relativeDirectory: relative_directory,
        exists: false,
        fileCount: 0,
        totalBytes: 0,
        truncated: false,
        latestEntries: []
      }
    end

    def safe_capture_directory(relative_directory)
      directory = @root.join(relative_directory)
      return unless directory.directory?

      resolved_root = @root.realpath
      resolved_directory = directory.realpath
      return unless inside?(resolved_directory, resolved_root)

      resolved_directory
    rescue Errno::EACCES, Errno::ENOENT, SystemCallError
      nil
    end

    def capture_files(directory)
      files = []
      truncated = false

      directory.each_child do |path|
        next if path.symlink? || !path.file?

        resolved = path.realpath
        next unless inside?(resolved, directory)

        if files.length >= MAX_CAPTURE_FILES
          truncated = true
          break
        end

        files << resolved
      rescue Errno::EACCES, Errno::ENOENT, SystemCallError
        next
      end

      [
        files.sort_by { |path| safe_file_mtime(path) }.reverse,
        truncated
      ]
    end

    def inside?(path, directory)
      path_string = path.to_s
      directory_string = directory.to_s
      path_string == directory_string ||
        path_string.start_with?("#{directory_string}#{File::SEPARATOR}")
    end

    def safe_file_size(path)
      path.size
    rescue Errno::EACCES, Errno::ENOENT, SystemCallError
      0
    end

    def safe_file_mtime(path)
      path.mtime
    rescue Errno::EACCES, Errno::ENOENT, SystemCallError
      Time.at(0)
    end

    def mail_entries(files)
      files.first(MAX_CAPTURE_ENTRIES).map do |path|
        {
          capturedAt: safe_file_mtime(path).utc.iso8601(6),
          sizeBytes: safe_file_size(path)
        }
      end
    end

    def jsonl_entries(files, kind)
      entries = files.first(MAX_CAPTURE_ENTRIES).flat_map do |path|
        tail_lines(path).filter_map do |line|
          parsed = JSON.parse(line)
          sanitize_capture_entry(parsed, kind)
        rescue JSON::ParserError, TypeError
          nil
        end
      end

      entries
        .sort_by { |entry| entry.fetch(:capturedAt, "") }
        .reverse
        .first(MAX_CAPTURE_ENTRIES)
    end

    def tail_lines(path)
      size = safe_file_size(path)
      return [] if size.zero?

      length = [ size, MAX_CAPTURE_TAIL_BYTES ].min
      File.open(path, "rb") do |file|
        file.seek(size - length, IO::SEEK_SET)
        chunk = file.read(length).to_s
        lines = chunk.lines
        lines.shift if length < size
        lines.last(MAX_CAPTURE_ENTRIES).select do |line|
          line.bytesize <= MAX_CAPTURE_LINE_BYTES
        end
      end
    rescue Errno::EACCES, Errno::ENOENT, IOError, SystemCallError
      []
    end

    def sanitize_capture_entry(entry, kind)
      return unless entry.is_a?(Hash)

      capture_id = entry["id"].to_s
      captured_at = safe_iso8601(entry["captured_at"])
      return unless capture_id.match?(UUID_PATTERN) && captured_at

      base = {
        captureRef: capture_id.first(8).downcase,
        capturedAt: captured_at
      }

      case kind
      when :webhooks
        method = entry["method"].to_s.upcase
        base.merge(method: HTTP_METHODS.include?(method) ? method : "OTHER")
      when :webPush
        notification_type = entry.dig("notification", "type").to_s
        base.merge(
          notificationType:
            notification_type.match?(SAFE_TOKEN_PATTERN) ?
              notification_type :
              "other"
        )
      end
    end

    def safe_iso8601(value)
      Time.iso8601(value.to_s).utc.iso8601(6)
    rescue ArgumentError
      nil
    end

    def minecraft_summary
      relation = Minecraft::NodeTask.where(
        "result ->> 'developer_mode' = ?",
        "true"
      )
      counts = relation.group(:status).count
      recent = relation
        .order(created_at: :desc)
        .limit(MAX_CAPTURE_ENTRIES)
        .pluck(:task_type, :status, :created_at, :completed_at)
        .map do |task_type, status, created_at, completed_at|
          {
            taskType: safe_token(task_type),
            status: safe_token(status),
            createdAt: created_at&.utc&.iso8601(6),
            completedAt: completed_at&.utc&.iso8601(6)
          }
        end

      {
        available: true,
        total: counts.values.sum,
        pending: counts.fetch("pending", 0),
        claimed: counts.fetch("claimed", 0),
        completed: counts.fetch("completed", 0),
        failed: counts.fetch("failed", 0),
        recent: recent
      }
    rescue ActiveRecord::ActiveRecordError
      {
        available: false,
        total: 0,
        pending: 0,
        claimed: 0,
        completed: 0,
        failed: 0,
        recent: []
      }
    end

    def safe_token(value)
      token = value.to_s
      token.match?(SAFE_TOKEN_PATTERN) ? token : "other"
    end

    def capture_browser(kind:, page:)
      Operations::DeveloperCaptureStore.new(root: @root).page(
        kind: kind,
        page: page
      )
    rescue ArgumentError
      Operations::DeveloperCaptureStore.new(root: @root).page(
        kind: "mail",
        page: 1
      )
    end

    def persona_summary
      users = User
        .where(developer_mode_persona: User::DEVELOPER_MODE_PERSONAS)
        .pluck(:developer_mode_persona, :status)
        .to_h

      User::DEVELOPER_MODE_PERSONAS.map do |persona|
        {
          key: persona,
          available: users[persona] == "active"
        }
      end
    rescue ActiveRecord::ActiveRecordError
      User::DEVELOPER_MODE_PERSONAS.map do |persona|
        { key: persona, available: false }
      end
    end

    def diagnostic_summary(settings)
      {
        application: "McWeb",
        environment: Rails.env,
        railsVersion: Rails.version,
        rubyVersion: RUBY_VERSION,
        developerMode: {
          enabled: settings.enabled?,
          profile: settings.profile.to_s,
          productionEnvironment: Rails.env.production?,
          autoLoginConfigured: settings.auto_login_user.present?,
          scheduledJobsAutoRegistration:
            Mcweb::SidekiqCronSchedule.automatic_registration_enabled?(
              settings: settings
            ),
          security: active_configuration(settings.security),
          integrations: active_configuration(settings.integrations),
          runtime: active_configuration(settings.runtime)
        }
      }
    end
  end
end
