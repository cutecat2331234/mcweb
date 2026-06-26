# frozen_string_literal: true

module Admin
  module Forum
    # Read-only view of the app's recurring scheduled jobs (from the static
    # sidekiq-cron schedule). No Redis dependency — reads the config file.
    class ScheduledTasksController < BaseController
      before_action -> { require_permission("forum.sections.manage") }

      SCHEDULE_PATH = Rails.root.join("config", "sidekiq_cron.yml")

      def index
        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("scheduled_tasks.title"),
          subtitle: forum_t("scheduled_tasks.description"),
          columns: [
            admin_column(:name, forum_t("scheduled_tasks.col_name")),
            admin_column(:cron, forum_t("scheduled_tasks.col_cron")),
            admin_column(:job, forum_t("scheduled_tasks.col_job")),
            admin_column(:queue, forum_t("scheduled_tasks.col_queue"))
          ],
          rows: scheduled_jobs.map do |name, config|
            admin_row(
              name: name.to_s.humanize,
              cron: config["cron"].to_s,
              job: config["class"].to_s,
              queue: config["queue"].to_s.presence || "default"
            )
          end
        }
      end

      private

      def scheduled_jobs
        return {} unless File.exist?(SCHEDULE_PATH)

        YAML.safe_load_file(SCHEDULE_PATH) || {}
      rescue StandardError
        {}
      end
    end
  end
end
