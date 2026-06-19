# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    before_action -> { require_permission("system.settings.manage") }
    before_action :set_user, only: %i[show edit update destroy ban unban grant_badge warn staff_note silence unsilence set_trust_level adjust_store_credit]

    def index
      users_scope = User.order(created_at: :desc)
      if params[:q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
        users_scope = users_scope.where("username ILIKE :q OR email ILIKE :q", q: q)
      end
      @pagy, users = pagy(users_scope, limit: 50)

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
        end,
        pagination: pagy_props(@pagy)
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
          { label: "账户类型", value: account_type_label(@user.account_type) },
          { label: "邮箱已验证", value: @user.email_verified? ? "是" : "否" },
          { label: "注册时间", value: l(@user.created_at, format: :long) },
          { label: "警告积分", value: Community::UserWarning.total_points_for(@user).to_s },
          { label: "沉默状态", value: @user.silenced? ? "是（可浏览不可发帖）" : "否" },
          { label: "信任等级", value: trust_level_label(@user) },
          { label: "信任等级覆盖", value: @user.forum_trust_level_override.present? ? "TL#{@user.forum_trust_level_override}" : "自动（按发帖数）" },
          { label: "商店余额", value: format_money(@user.store_credit_cents.to_i, "CNY") }
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
          },
          {
            title: "员工备注（仅管理可见）",
            items: @user.forum_staff_notes.recent.limit(5).map do |note|
              { label: "#{note.author.username} · #{l(note.created_at, format: :short)}", value: note.body }
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
        staffNoteForm: current_user.permission?("forum.users.warn") || current_user.permission?("admin.access") ? {
          action_url: staff_note_admin_user_path(@user)
        } : nil,
        silenceForm: current_user.permission?("forum.users.mute") || current_user.permission?("admin.access") ? {
          silenced: @user.silenced?,
          silence_url: silence_admin_user_path(@user),
          unsilence_url: unsilence_admin_user_path(@user)
        } : nil,
        trustLevelForm: current_user.permission?("admin.access") || current_user.permission?("system.settings.manage") ? {
          action_url: set_trust_level_admin_user_path(@user),
          current_level: Community::TrustLevel.level_for(@user),
          override: @user.forum_trust_level_override,
          levels: Community::TrustLevel::LEVELS.map { |entry| { value: entry[:level], label: "TL#{entry[:level]} · #{entry[:name]}" } }
        } : nil,
        storeCreditForm: current_user.permission?("store.orders.read") || current_user.permission?("admin.access") ? {
          action_url: adjust_store_credit_admin_user_path(@user),
          balance_cents: @user.store_credit_cents.to_i,
          balance_label: format_money(@user.store_credit_cents.to_i, "CNY")
        } : nil,
        accountForm: current_user.account_owner? || current_user.permission?("system.settings.manage") ? {
          action_url: admin_user_path(@user),
          account_type: @user.account_type,
          account_types: User.account_types.keys.map { |key| { value: key, label: account_type_label(key) } },
          role_ids: @user.role_ids,
          roles: Role.order(:name).map { |role| { id: role.id, name: role.name, key: role.key } },
          admin_modules: @user.admin_module_grants.pluck(:module_key),
          module_options: AdminModuleGrant::MODULE_KEYS
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
        sync_roles_and_modules!
        Administration::AuditLogger.call(actor: current_user, action: "admin.user_updated", resource: @user)
        redirect_to admin_user_path(@user), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.user"))
      else
        redirect_to admin_user_path(@user), alert: @user.errors.full_messages.to_sentence
      end
    end

    def destroy
      @user.soft_delete!
      Administration::AuditLogger.call(actor: current_user, action: "admin.user_deleted", resource: @user)
      redirect_to admin_users_path, notice: t("mcweb.flash.deleted", resource: t("mcweb.resources.user"))
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
        redirect_to admin_user_path(@user), notice: t("mcweb.flash.user_banned")
      else
        redirect_to admin_user_path(@user), alert: service_error_message(result)
      end
    end

    def unban
      result = Administration::UnbanUser.call(user: @user, actor: current_user)
      if result.success?
        redirect_to admin_user_path(@user), notice: t("mcweb.flash.user_unbanned")
      else
        redirect_to admin_user_path(@user), alert: service_error_message(result)
      end
    end

    def grant_badge
      return redirect_to admin_user_path(@user), alert: t("mcweb.flash.cannot_grant_badge") unless current_user.permission?("forum.badges.manage") || current_user.permission?("admin.access")

      result = Community::AwardBadge.call(user: @user, badge_slug: params[:badge_slug])
      if result.success?
        redirect_to admin_user_path(@user), notice: t("mcweb.flash.badge_granted")
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
        redirect_to admin_user_path(@user), notice: t("mcweb.flash.warning_issued")
      else
        redirect_to admin_user_path(@user), alert: service_error_message(result)
      end
    end

    def staff_note
      result = Community::CreateStaffNote.call(
        actor: current_user,
        user: @user,
        body: params[:body]
      )
      if result.success?
        redirect_to admin_user_path(@user), notice: t("mcweb.flash.staff_note_added")
      else
        redirect_to admin_user_path(@user), alert: service_error_message(result)
      end
    end

    def silence
      result = Community::CreateUserSilence.call(
        actor: current_user,
        user: @user,
        reason: params[:reason],
        days: params[:days]
      )
      if result.success?
        redirect_to admin_user_path(@user), notice: t("mcweb.flash.user_silenced")
      else
        redirect_to admin_user_path(@user), alert: service_error_message(result)
      end
    end

    def unsilence
      result = Community::RemoveUserSilence.call(actor: current_user, user: @user)
      if result.success?
        redirect_to admin_user_path(@user), notice: t("mcweb.flash.user_unsilenced")
      else
        redirect_to admin_user_path(@user), alert: service_error_message(result)
      end
    end

    def set_trust_level
      override = params[:forum_trust_level_override]
      value = override.to_s.strip
      if value.blank? || value == "auto"
        @user.update!(forum_trust_level_override: nil)
        redirect_to admin_user_path(@user), notice: t("mcweb.flash.trust_level_auto")
      else
        level = value.to_i
        unless level.between?(0, 4)
          return redirect_to admin_user_path(@user), alert: t("mcweb.flash.trust_level_invalid")
        end

        @user.update!(forum_trust_level_override: level)
        redirect_to admin_user_path(@user), notice: t("mcweb.flash.trust_level_set", level: level)
      end
    end

    def adjust_store_credit
      result = Commerce::AdjustStoreCredit.call(
        actor: current_user,
        user: @user,
        amount_cents: params[:amount_cents],
        note: params[:note]
      )
      if result.success?
        redirect_to admin_user_path(@user), notice: t("mcweb.flash.wallet_updated", amount: format_money(result.value[:balance_cents], "CNY"))
      else
        redirect_to admin_user_path(@user), alert: service_error_message(result)
      end
    end

    private

    def trust_level_label(user)
      level = Community::TrustLevel.level_for(user)
      info = Community::TrustLevel::LEVELS.find { |entry| entry[:level] == level }
      "TL#{level} · #{info&.dig(:name) || '未知'}"
    end

    def account_type_label(account_type)
      {
        "member" => "普通会员",
        "staff" => "工作人员",
        "admin" => "管理员",
        "owner" => "站主"
      }[account_type.to_s] || account_type.to_s
    end

    def sync_roles_and_modules!
      return unless params[:user]

      if params[:user][:role_ids]
        @user.role_ids = Array(params[:user][:role_ids]).reject(&:blank?).map(&:to_i)
      end

      if params[:user][:admin_modules] && (@user.account_staff? || params[:user][:account_type] == "staff")
        modules = Array(params[:user][:admin_modules]).reject(&:blank?)
        @user.admin_module_grants.where.not(module_key: modules).delete_all
        modules.each do |module_key|
          @user.admin_module_grants.find_or_create_by!(module_key: module_key) do |grant|
            grant.granted_by = current_user
            grant.granted_at = Time.current
          end
        end
      end
    end

    def set_user
      @user = User.find_by!(public_id: params[:id])
    end

    def user_params
      permitted = %i[display_name locale time_zone]
      permitted << :account_type if current_user.account_owner? || current_user.permission?("system.settings.manage")
      params.expect(user: permitted)[:user]
    end
  end
end
