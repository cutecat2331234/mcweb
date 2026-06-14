# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    before_action -> { require_permission("system.settings.manage") }
    before_action :set_user, only: %i[show edit update destroy ban unban]

    def index
      users = User.order(created_at: :desc)

      render inertia: "Admin/Generic/Index", props: {
        title: "用户",
        columns: [
          admin_column(:username, "用户名", link: true),
          admin_column(:email, "邮箱"),
          admin_column(:status, "状态"),
          admin_column(:joined, "注册时间")
        ],
        rows: users.map do |user|
          admin_row(
            username: user.username,
            email: user.email,
            status: user.status,
            joined: l(user.created_at, format: :short),
            url: admin_user_path(user)
          )
        end
      }
    end

    def show
      mutes = Community::Mute.active.where(user: @user).includes(:section, :created_by)
      mute_actions = if current_user.permission?("forum.users.mute")
                       mutes.map do |mute|
                         {
                           id: mute.id,
                           section: mute.section&.name || "全站",
                           reason: mute.reason,
                           expires_at: mute.expires_at ? l(mute.expires_at, format: :short) : "永久",
                           remove_url: admin_forum_mute_path(mute)
                         }
                       end
                     else
                       []
                     end

      render inertia: "Admin/Generic/Show", props: {
        title: @user.display_name.presence || @user.username,
        subtitle: @user.email,
        fields: [
          { label: "用户名", value: @user.username },
          { label: "状态", value: @user.status },
          { label: "封禁原因", value: @user.ban_reason.presence || "—" },
          { label: "封禁到期", value: @user.ban_expires_at ? l(@user.ban_expires_at, format: :long) : (@user.banned? ? "永久" : "—") },
          { label: "角色", value: @user.roles.pluck(:name).join(", ").presence || "—" },
          { label: "邮箱已验证", value: @user.email_verified? ? "是" : "否" },
          { label: "注册时间", value: l(@user.created_at, format: :long) },
          { label: "警告积分", value: Community::UserWarning.total_points_for(@user).to_s }
        ],
        sections: [
          mute_actions.any? ? {
            title: "当前禁言",
            items: mute_actions.map { |m| { label: m[:section], value: "#{m[:reason] || '—'} · 到期: #{m[:expires_at]}" } }
          } : nil,
          {
            title: "社区警告",
            items: @user.forum_warnings.recent.limit(5).map do |warning|
              { label: l(warning.created_at, format: :short), value: "#{warning.points} 点 · #{warning.reason}" }
            end.presence || [ { label: "记录", value: "无" } ]
          }
        ].compact,
        backUrl: admin_users_path,
        muteForm: current_user.permission?("forum.users.mute") ? {
          user_id: @user.public_id,
          action_url: admin_forum_mutes_path
        } : nil,
        banForm: {
          banned: @user.banned?,
          ban_url: ban_admin_user_path(@user),
          unban_url: unban_admin_user_path(@user)
        },
        badgeForm: current_user.permission?("forum.badges.manage") || current_user.permission?("admin.access") ? {
          action_url: grant_badge_admin_user_path(@user),
          badges: Community::Badge.order(:name).map { |badge| { slug: badge.slug, name: badge.name } },
          earned: @user.user_badges.includes(:badge).map { |ub| ub.badge.name }
        } : nil,
        warningForm: current_user.permission?("forum.users.warn") || current_user.permission?("admin.access") ? {
          action_url: warn_admin_user_path(@user),
          warning_points: Community::UserWarning.total_points_for(@user)
        } : nil,
        actions: mute_actions.map do |m|
          { label: "解除禁言 (#{m[:section]})", href: m[:remove_url], method: "delete" }
        end
      }
    end

    def edit
    end

    def update
      if @user.update(user_params)
        Administration::AuditLogger.call(actor: current_user, action: "admin.user_updated", resource: @user)
        redirect_to admin_user_path(@user), notice: "User updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @user.soft_delete!
      Administration::AuditLogger.call(actor: current_user, action: "admin.user_deleted", resource: @user)
      redirect_to admin_users_path, notice: "User deleted."
    end

    def ban
      expires_at = params[:expires_at].present? ? Time.zone.parse(params[:expires_at]) : nil
      result = Administration::BanUser.call(
        user: @user,
        actor: current_user,
        reason: params[:reason],
        expires_at: expires_at
      )

      if result.success?
        redirect_to admin_user_path(@user), notice: "用户已封禁。"
      else
        redirect_to admin_user_path(@user), alert: service_error_message(result)
      end
    end

    def unban
      result = Administration::UnbanUser.call(user: @user, actor: current_user)
      if result.success?
        redirect_to admin_user_path(@user), notice: "用户已解封。"
      else
        redirect_to admin_user_path(@user), alert: service_error_message(result)
      end
    end

    def grant_badge
      return redirect_to admin_user_path(@user), alert: "无权授予徽章。" unless current_user.permission?("forum.badges.manage") || current_user.permission?("admin.access")

      result = Community::AwardBadge.call(user: @user, badge_slug: params[:badge_slug])
      if result.success?
        redirect_to admin_user_path(@user), notice: "徽章已授予。"
      else
        redirect_to admin_user_path(@user), alert: service_error_message(result)
      end
    end

    def warn
      result = Community::CreateUserWarning.call(
        actor: current_user,
        user: @user,
        reason: params[:reason],
        points: params[:points]
      )
      if result.success?
        redirect_to admin_user_path(@user), notice: "警告已发出。"
      else
        redirect_to admin_user_path(@user), alert: service_error_message(result)
      end
    end

    private

    def set_user
      @user = User.find_by!(public_id: params[:id])
    end

    def user_params
      params.expect(user: %i[display_name locale time_zone status])[:user]
    end
  end
end
