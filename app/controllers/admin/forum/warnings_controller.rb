# frozen_string_literal: true

module Admin
  module Forum
    class WarningsController < BaseController
      before_action -> { require_permission("forum.users.warn") }

      def index
        warnings = Community::UserWarning.includes(:user, :issuer).order(created_at: :desc)
        if params[:user].present?
          user = User.find_by(username: params[:user])
          warnings = warnings.where(user_id: user.id) if user
        end

        if params[:format] == "csv"
          return export_warnings(warnings.limit(5000))
        end

        @pagy, warnings = pagy(warnings, limit: 50)

        render inertia: "Admin/Generic/Index", props: {
          title: "用户警告记录",
          exportUrl: admin_forum_warnings_path(format: :csv, user: params[:user]),
          columns: [
            { key: "user", label: "用户" },
            { key: "issuer", label: "发出者" },
            { key: "points", label: "积分" },
            { key: "reason", label: "原因" },
            { key: "created_at", label: "时间" }
          ],
          rows: warnings.map do |warning|
            {
              id: warning.id,
              user: warning.user.username,
              issuer: warning.issuer.username,
              points: warning.points.to_s,
              reason: warning.reason.truncate(80),
              created_at: l(warning.created_at, format: :short),
              url: admin_user_path(warning.user)
            }
          end,
          pagination: pagy_props(@pagy)
        }
      end

      private

      def export_warnings(scope)
        csv = CSV.generate(headers: true) do |rows|
          rows << %w[用户 发出者 积分 原因 时间]
          scope.find_each do |warning|
            rows << [
              warning.user.username,
              warning.issuer.username,
              warning.points,
              warning.reason,
              warning.created_at.iso8601
            ]
          end
        end
        send_data csv, filename: "forum-warnings-#{Date.current}.csv", type: "text/csv"
      end
    end
  end
end
