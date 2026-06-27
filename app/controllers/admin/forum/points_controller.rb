# frozen_string_literal: true

module Admin
  module Forum
    class PointsController < Admin::Forum::BaseController
      before_action -> { require_permission("forum.points.manage") }

      POINT_SETTING_KEYS = %w[
        forum.points.post_created
        forum.points.reaction_received
        forum.points.solution_accepted
      ].freeze

      DEFAULTS = {
        "forum.points.post_created" => "5",
        "forum.points.reaction_received" => "2",
        "forum.points.solution_accepted" => "15"
      }.freeze

      # GET /admin/forum/points - paginated transactions log
      def index
        scope = Community::PointTransaction.includes(:user, :source).order(created_at: :desc)
        if params[:user].present?
          scope = scope.joins(:user).where("users.username ILIKE ?", "%#{params[:user].to_s.strip}%")
        end

        @pagy, rows = pagy(:offset, scope, limit: 50)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.forum.points.log_title"),
          subtitle: t("mcweb.admin.forum.points.log_subtitle"),
          columns: [
            admin_column("created_at", t("mcweb.admin.forum.points.col_created_at")),
            admin_column("user", t("mcweb.admin.forum.points.col_user"), link: true),
            admin_column("amount", t("mcweb.admin.forum.points.col_amount")),
            admin_column("reason", t("mcweb.admin.forum.points.col_reason")),
            admin_column("balance_after", t("mcweb.admin.forum.points.col_balance_after")),
            admin_column("source", t("mcweb.admin.forum.points.col_source"))
          ],
          rows: rows.map { |tx| transaction_row(tx) },
          actions: [
            { label: t("mcweb.admin.forum.points.adjust_action"), href: admin_forum_adjust_points_path },
            { label: t("mcweb.admin.forum.points.settings_action"), href: admin_forum_points_settings_path }
          ],
          pagination: pagy_props(@pagy)
        }
      end

      # GET /admin/forum/points/settings
      def settings
        render inertia: "Admin/Forum/Points/Settings", props: {
          settings: settings_props,
          save_url: admin_forum_points_settings_path,
          back_url: admin_forum_points_path
        }
      end

      # PATCH /admin/forum/points/settings
      def update_settings
        settings_params.each do |key, value|
          SiteSetting.set(key, value.to_s)
        end

        Administration::AuditLogger.call(
          actor: current_user,
          action: "admin.forum_points_settings_updated",
          metadata: settings_params.to_h
        )

        redirect_to admin_forum_points_settings_path, notice: t("mcweb.flash.point_settings_saved")
      end

      # GET /admin/forum/points/adjust
      def new_adjustment
        render inertia: "Admin/Forum/Points/Adjust", props: {
          save_url: admin_forum_adjust_points_path,
          back_url: admin_forum_points_path
        }
      end

      # POST /admin/forum/points/adjust
      def create_adjustment
        target = find_target_user
        unless target
          return redirect_to admin_forum_adjust_points_path, alert: t("mcweb.flash.point_user_not_found")
        end

        amount = params[:amount].to_i
        if amount.zero?
          return redirect_to admin_forum_adjust_points_path, alert: t("mcweb.flash.point_amount_required")
        end

        result = Community::AwardPoints.call(
          user: target,
          amount: amount,
          reason: "admin_adjust",
          actor: current_user,
          note: params[:note].to_s.presence,
          dedupe_token: nil
        )

        if result.success?
          Administration::AuditLogger.call(
            actor: current_user,
            action: "admin.forum_points_adjusted",
            resource: target,
            metadata: { amount: amount, note: params[:note].to_s.presence }
          )
          redirect_to admin_forum_points_path, notice: t("mcweb.flash.point_adjustment_saved")
        else
          redirect_to admin_forum_adjust_points_path, alert: result.error || t("mcweb.flash.point_adjustment_failed")
        end
      end

      private

      def settings_props
        POINT_SETTING_KEYS.map do |key|
          {
            key: key,
            value: SiteSetting.get(key, DEFAULTS[key]).to_s,
            label: t("mcweb.admin.forum.points.labels.#{key}"),
            hint: t("mcweb.admin.forum.points.hints.#{key}")
          }
        end
      end

      def settings_params
        allowed = POINT_SETTING_KEYS.index_with { |_k| nil }
        params.fetch(:settings, {}).permit(*allowed.keys).to_h
      end

      def find_target_user
        identifier = params[:username].to_s.strip
        return nil if identifier.blank?

        User.find_by(username: identifier) || User.find_by(id: identifier)
      end

      def transaction_row(tx)
        admin_row(
          created_at: l(tx.created_at, format: :short),
          user: tx.user&.username,
          amount: format_amount(tx.amount),
          reason: t("mcweb.admin.forum.points.reasons.#{tx.reason}", default: tx.reason),
          balance_after: tx.balance_after,
          source: source_label(tx),
          url: tx.user ? forum_user_path(tx.user.username) : nil
        )
      end

      def format_amount(amount)
        amount.positive? ? "+#{amount}" : amount.to_s
      end

      def source_label(tx)
        return "—" if tx.source_type.blank?

        "#{tx.source_type.demodulize}##{tx.source_id}"
      end
    end
  end
end
