# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    before_action -> { require_admin_module!("system") },
                  except: %i[
                    store_credit_index
                    store_credit_show
                    authorize_store_credit_adjustment
                    adjust_store_credit
                  ]
    before_action -> { require_permission("system.settings.manage") },
                  only: %i[index show edit update destroy ban unban]
    before_action -> { require_permission("identity.permissions.explain") },
                  only: :permission_explanation
    before_action -> { require_admin_module!("forum") },
                  only: %i[grant_badge revoke_badge warn staff_note clean_spam silence unsilence set_trust_level]
    before_action -> { require_permission("forum.badges.manage") },
                  only: %i[grant_badge revoke_badge]
    before_action -> { require_permission("forum.users.warn") },
                  only: %i[warn staff_note clean_spam]
    before_action -> { require_permission("forum.users.mute") },
                  only: %i[silence unsilence]
    before_action -> { require_permission("forum.users.trust.manage") },
                  only: :set_trust_level
    before_action -> { require_admin_module!("store") },
                  only: %i[
                    store_credit_index
                    store_credit_show
                    authorize_store_credit_adjustment
                    adjust_store_credit
                  ]
    before_action -> { require_permission("store.credit.read") },
                  only: %i[
                    store_credit_index
                    store_credit_show
                  ]
    before_action -> { require_permission("store.credit.adjust") },
                  only: %i[
                    authorize_store_credit_adjustment
                    adjust_store_credit
                  ]
    before_action :set_user, only: %i[show permission_explanation store_credit_show edit update destroy ban unban grant_badge revoke_badge warn staff_note silence unsilence set_trust_level authorize_store_credit_adjustment adjust_store_credit clean_spam]
    before_action :ensure_store_credit_target_manageable!, only: :store_credit_show
    before_action :ensure_manageable_target!,
                  only: %i[ban unban silence unsilence set_trust_level authorize_store_credit_adjustment adjust_store_credit warn staff_note grant_badge revoke_badge clean_spam]

    def index
      users_scope = User.order(created_at: :desc)
      if params[:q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
        users_scope = users_scope.where("username ILIKE :q OR email ILIKE :q", q: q)
      end
      @pagy, users = pagy(:offset, users_scope, limit: 50)

      render inertia: "Admin/Generic/Index", props: {
        title: t("mcweb.admin.users.title"),
        columns: [
          admin_column(:username, t("mcweb.admin.users.fields.username"), link: true),
          admin_column(:email, t("mcweb.admin.users.fields.email")),
          admin_column(:status, t("mcweb.admin.users.fields.status")),
          admin_column(:joined, t("mcweb.admin.users.fields.joined_at"))
        ],
        rows: users.map do |user|
          admin_row(
            username: user.username,
            email: user.email,
            status: user_status_label(user.status),
            joined: l(user.created_at, format: :short),
            url: admin_user_path(user)
          )
        end,
        pagination: pagy_props(@pagy)
      }
    end

    def store_credit_index
      users_scope = store_credit_manageable_users_scope.order(created_at: :desc)
      if params[:q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
        users_scope = users_scope.where(
          "username ILIKE :q OR display_name ILIKE :q",
          q: q
        )
      end
      @pagy, users = pagy(:offset, users_scope, limit: 50)

      render inertia: "Admin/Generic/Index", props: {
        title: t("mcweb.admin.store_credit_users.title"),
        subtitle: t("mcweb.admin.store_credit_users.subtitle"),
        columns: [
          admin_column(
            :username,
            t("mcweb.admin.store_credit_users.col_username"),
            link: true
          ),
          admin_column(
            :store_credit,
            t("mcweb.admin.store_credit_users.col_balance")
          )
        ],
        rows: users.map do |user|
          admin_row(
            username: user.username,
            store_credit: format_money(user.store_credit_cents.to_i, "CNY"),
            url: admin_store_credit_user_path(user)
          )
        end,
        search: {
          query: params[:q].to_s.strip,
          placeholder: t("mcweb.admin.store_credit_users.search_placeholder"),
          action: admin_store_credit_users_path
        },
        pagination: pagy_props(@pagy)
      }
    end

    def store_credit_show
      render inertia: "Admin/Generic/Show", props: {
        title: @user.username,
        subtitle: t("mcweb.admin.store_credit_users.detail_subtitle"),
        fields: [
          {
            label: t("mcweb.admin.store_credit_users.field_username"),
            value: @user.username
          },
          {
            key: "store_credit",
            label: t("mcweb.admin.store_credit_users.field_balance"),
            value: format_money(@user.store_credit_cents.to_i, "CNY")
          }
        ],
        sections: [],
        backUrl: admin_store_credit_users_path,
        storeCreditForm: store_credit_form_props
      }
    end

    def show
      mutes = Community::Mute.active.where(user: @user).includes(:section, :created_by)
      mute_actions = if allowed_user_action?("forum", "forum.users.mute")
                       mutes.map do |mute|
                         {
                           id: mute.id,
                           section: mute.section&.name || t("mcweb.admin.users.global_scope"),
                           reason: mute.reason,
                           expires_at: mute.expires_at ? l(mute.expires_at, format: :short) : t("mcweb.admin.users.permanent"),
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
          { label: t("mcweb.admin.users.fields.username"), value: @user.username },
          { label: t("mcweb.admin.users.fields.status"), value: user_status_label(@user.status) },
          { label: t("mcweb.admin.users.fields.ban_reason"), value: @user.ban_reason.presence || not_available_label },
          { label: t("mcweb.admin.users.fields.ban_expires_at"), value: @user.ban_expires_at ? l(@user.ban_expires_at, format: :long) : (@user.banned? ? t("mcweb.admin.users.permanent") : not_available_label) },
          { label: t("mcweb.admin.users.fields.roles"), value: @user.roles.pluck(:name).join(", ").presence || not_available_label },
          { label: t("mcweb.admin.users.fields.account_type"), value: account_type_label(@user.account_type) },
          { label: t("mcweb.admin.users.fields.email_verified"), value: boolean_label(@user.email_verified?) },
          { label: t("mcweb.admin.users.fields.joined_at"), value: l(@user.created_at, format: :long) },
          { label: t("mcweb.admin.users.fields.warning_points"), value: Community::UserWarning.total_points_for(@user).to_s },
          { label: t("mcweb.admin.users.fields.silence_status"), value: @user.silenced? ? t("mcweb.admin.users.silenced") : t("mcweb.admin.users.not_silenced") },
          { label: t("mcweb.admin.users.fields.trust_level"), value: trust_level_label(@user) },
          { label: t("mcweb.admin.users.fields.trust_override"), value: @user.forum_trust_level_override.present? ? "TL#{@user.forum_trust_level_override}" : t("mcweb.admin.users.trust_automatic") },
          allowed_user_action?("store", "store.credit.read") ? {
            key: "store_credit",
            label: t("mcweb.admin.users.fields.store_credit"),
            value: format_money(@user.store_credit_cents.to_i, "CNY")
          } : nil
        ].compact,
        sections: [
          mute_actions.any? ? {
            title: t("mcweb.admin.users.sections.active_mutes"),
            items: mute_actions.map do |mute|
              {
                label: mute[:section],
                value: t(
                  "mcweb.admin.users.mute_summary",
                  reason: mute[:reason].presence || not_available_label,
                  expires_at: mute[:expires_at]
                )
              }
            end
          } : nil,
          {
            title: t("mcweb.admin.users.sections.warnings"),
            items: @user.forum_warnings.recent.limit(5).map do |warning|
              {
                label: l(warning.created_at, format: :short),
                value: t("mcweb.admin.users.warning_summary", points: warning.points, reason: warning.reason)
              }
            end.presence || empty_record_items
          },
          {
            title: t("mcweb.admin.users.sections.staff_notes"),
            items: @user.forum_staff_notes.recent.limit(5).map do |note|
              { label: "#{note.author.username} · #{l(note.created_at, format: :short)}", value: note.body }
            end.presence || empty_record_items
          }
        ].compact,
        backUrl: admin_users_path,
        muteForm: allowed_user_action?("forum", "forum.users.mute") ? {
          user_id: @user.public_id,
          action_url: admin_forum_mutes_path
        } : nil,
        banForm: {
          banned: @user.banned?,
          ban_url: ban_admin_user_path(@user),
          unban_url: unban_admin_user_path(@user)
        },
        badgeForm: allowed_user_action?("forum", "forum.badges.manage") ? {
          action_url: grant_badge_admin_user_path(@user),
          revoke_url: revoke_badge_admin_user_path(@user),
          badges: Community::Badge.order(:name).map { |badge| { slug: badge.slug, name: badge.name } },
          earned: @user.user_badges.includes(:badge).map { |ub| ub.badge.name }
        } : nil,
        warningForm: allowed_user_action?("forum", "forum.users.warn") ? {
          action_url: warn_admin_user_path(@user),
          warning_points: Community::UserWarning.total_points_for(@user)
        } : nil,
        staffNoteForm: allowed_user_action?("forum", "forum.users.warn") ? {
          action_url: staff_note_admin_user_path(@user)
        } : nil,
        spamCleanForm: allowed_user_action?("forum", "forum.users.warn") && manageable_user?(@user) ? {
          action_url: clean_spam_admin_user_path(@user)
        } : nil,
        silenceForm: allowed_user_action?("forum", "forum.users.mute") ? {
          silenced: @user.silenced?,
          silence_url: silence_admin_user_path(@user),
          unsilence_url: unsilence_admin_user_path(@user)
        } : nil,
        trustLevelForm: allowed_user_action?("forum", "forum.users.trust.manage") ? {
          action_url: set_trust_level_admin_user_path(@user),
          current_level: Community::TrustLevel.level_for(@user),
          override: @user.forum_trust_level_override,
          levels: Community::TrustLevel::LEVELS.map do |entry|
            { value: entry[:level], label: trust_level_option_label(entry[:level]) }
          end
        } : nil,
        storeCreditForm: store_credit_form_props,
        accountForm: account_form_props,
        actions: (
          mute_actions.map do |m|
          {
            label: t("mcweb.admin.users.remove_mute", section: m[:section]),
            href: m[:remove_url],
            method: "delete"
          }
          end +
          if allowed_user_action?("system", "identity.permissions.explain")
            [ {
              label: t("mcweb.permission_explanation.open"),
              href: permissions_admin_user_path(@user),
              method: "get"
            } ]
          else
            []
          end
        )
      }
    end

    def permission_explanation
      result = Identity::PermissionExplanation.call(user: @user, locale: I18n.locale)
      return redirect_to admin_user_path(@user), alert: service_error_message(result) unless result.success?

      render inertia: "Admin/Users/Permissions", props: result.value.merge(
        backUrl: admin_user_path(@user)
      )
    end

    def edit
    end

    def update
      unless manageable_user?(@user)
        return redirect_to admin_user_path(@user), alert: t("mcweb.flash.permission_denied")
      end

      unknown_modules = unknown_requested_admin_modules
      if unknown_modules.any?
        return redirect_to(
          admin_user_path(@user),
          alert: t("mcweb.flash.admin_module_denied")
        )
      end

      updated = false
      User.transaction do
        Identity::PermissionMutationLock.acquire_exclusive! if role_ids_update_requested?
        updated = @user.update(user_params)
        sync_roles_and_modules! if updated
        if updated
          Administration::AuditLogger.call(
            actor: current_user,
            action: "admin.user_updated",
            resource: @user
          )
        end
      end

      if updated
        redirect_to admin_user_path(@user), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.user"))
      else
        redirect_to admin_user_path(@user), alert: @user.errors.full_messages.to_sentence
      end
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_user_path(@user), alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      unless manageable_user?(@user)
        return redirect_to admin_users_path, alert: t("mcweb.flash.permission_denied")
      end

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
      result = Community::AwardBadge.call(user: @user, badge_slug: params[:badge_slug])
      if result.success?
        redirect_to admin_user_path(@user), notice: t("mcweb.flash.badge_granted")
      else
        redirect_to admin_user_path(@user), alert: service_error_message(result)
      end
    end

    def revoke_badge
      result = Community::RevokeBadge.call(user: @user, badge_slug: params[:badge_slug])
      if result.success?
        redirect_to admin_user_path(@user), notice: t("mcweb.flash.badge_revoked")
      else
        redirect_to admin_user_path(@user), alert: service_error_message(result)
      end
    end

    def warn
      result = Community::CreateUserWarning.call(
        actor: current_user,
        user: @user,
        reason: params[:reason],
        points: params[:points],
        expire_days: params[:expire_days]
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

    def clean_spam
      result = Community::SpamCleaner.call(actor: current_user, user: @user, ban: true)
      if result.success?
        redirect_to admin_user_path(@user), notice: t("mcweb.flash.spam_cleaned", topics: result.value[:topics], posts: result.value[:posts])
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

    def authorize_store_credit_adjustment
      result = Commerce::StoreCreditAdjustmentAuthorization.issue(
        actor: current_user,
        user: @user,
        amount_cents: params[:amount_cents],
        request_id: params[:request_id],
        note: params[:note]
      )

      response.set_header("Cache-Control", "no-store")
      if result.success?
        render json: {
          token: result.value[:token],
          confirmation: result.value[:confirmation],
          request_id: result.value[:request_id],
          expires_in: result.value[:expires_in],
          amount_cents: result.value[:amount_cents],
          amount_label: format_money(result.value[:amount_cents], "CNY"),
          balance_before_cents: result.value[:balance_before_cents],
          balance_before_label: format_money(result.value[:balance_before_cents], "CNY"),
          balance_after_cents: result.value[:balance_after_cents],
          balance_after_label: format_money(result.value[:balance_after_cents], "CNY")
        }
      else
        render json: { error: service_error_message(result) },
               status: service_error_status(result)
      end
    end

    def adjust_store_credit
      result = Commerce::AdjustStoreCredit.call(
        actor: current_user,
        user: @user,
        amount_cents: params[:amount_cents],
        request_id: params[:request_id],
        authorization_token: params[:authorization_token],
        confirmation: params[:confirmation],
        note: params[:note],
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
      if result.success?
        if request.format.json?
          response.set_header("Cache-Control", "no-store")
          render json: {
            balance_cents: result.value[:balance_cents],
            balance_label: format_money(result.value[:balance_cents], "CNY"),
            request_id: result.value[:request_id],
            idempotent: result.value[:idempotent]
          }
        else
          redirect_to admin_user_path(@user), notice: t("mcweb.flash.wallet_updated", amount: format_money(result.value[:balance_cents], "CNY"))
        end
      else
        if request.format.json?
          response.set_header("Cache-Control", "no-store")
          render json: { error: service_error_message(result) },
                 status: service_error_status(result)
        else
          redirect_to admin_user_path(@user), alert: service_error_message(result)
        end
      end
    end

    private

    def trust_level_label(user)
      trust_level_option_label(Community::TrustLevel.level_for(user))
    end

    def trust_level_option_label(level)
      name = t("mcweb.admin.users.trust_levels.tl#{level}", default: t("mcweb.admin.users.unknown"))
      "TL#{level} · #{name}"
    end

    def account_type_label(account_type)
      t(
        "mcweb.admin.users.account_types.#{account_type}",
        default: t("mcweb.admin.users.unknown")
      )
    end

    def user_status_label(status)
      t("mcweb.admin.users.statuses.#{status}", default: t("mcweb.admin.users.unknown"))
    end

    def boolean_label(value)
      t(value ? "mcweb.admin.users.boolean_yes" : "mcweb.admin.users.boolean_no")
    end

    def not_available_label
      t("mcweb.admin.users.not_available")
    end

    def empty_record_items
      [ {
        label: t("mcweb.admin.users.record"),
        value: t("mcweb.admin.users.none")
      } ]
    end

    def sync_roles_and_modules!
      return unless params[:user]

      permission_context_changed = false
      if role_ids_update_requested?
        requested_role_ids = Array(params[:user][:role_ids]).reject(&:blank?).map(&:to_i).uniq.sort
        permission_context_changed ||= @user.role_ids.sort != requested_role_ids
        @user.role_ids = requested_role_ids
      end

      if current_user.account_owner?
        if @user.account_staff? && params[:user].key?(:admin_modules)
          modules = requested_admin_modules
          permission_context_changed ||= @user.admin_module_grants.pluck(:module_key).sort != modules.sort
          @user.admin_module_grants.where.not(module_key: modules).delete_all
          modules.each do |module_key|
            @user.admin_module_grants.find_or_create_by!(module_key: module_key) do |grant|
              grant.granted_by = current_user
              grant.granted_at = Time.current
            end
          end
        elsif !@user.account_staff? || @user.saved_change_to_account_type?
          permission_context_changed ||= @user.admin_module_grants.exists?
          @user.admin_module_grants.delete_all
        end
      end
      Identity::PermissionVersion.bump_users!([ @user.id ]) if permission_context_changed
    end

    def role_ids_update_requested?
      current_user.account_owner? && params[:user]&.[](:role_ids)
    end

    def requested_admin_modules
      Array(params.dig(:user, :admin_modules)).reject(&:blank?).map(&:to_s).uniq
    end

    def unknown_requested_admin_modules
      return [] unless current_user.account_owner?
      return [] unless params[:user]&.key?(:admin_modules)

      requested_admin_modules - AdminModuleGrant::MODULE_KEYS
    end

    def set_user
      @user = User.find_by!(public_id: params[:id])
    end

    def user_params
      permitted = %i[display_name locale time_zone]
      permitted << :account_type if current_user.account_owner?
      params.fetch(:user, ActionController::Parameters.new).permit(permitted)
    end

    def account_form_props
      return nil unless current_user.account_owner? || current_user.permission?("system.settings.manage")

      props = {
        action_url: admin_user_path(@user)
      }

      if current_user.account_owner?
        props.merge!(
          admin_modules: @user.admin_module_grants.pluck(:module_key) & AdminModuleGrant::MODULE_KEYS,
          module_options: AdminModuleGrant::MODULE_KEYS,
          account_type: @user.account_type,
          account_types: User.account_types.keys.map { |key| { value: key, label: account_type_label(key) } },
          role_ids: @user.role_ids,
          roles: Role.order(:name).map { |role| { id: role.id, name: role.name, key: role.key } }
        )
      end

      props
    end

    def manageable_user?(user)
      return false if user.account_owner? && !current_user.account_owner?

      true
    end

    def store_credit_target_manageable?(user)
      user != current_user && manageable_user?(user)
    end

    def store_credit_manageable_users_scope
      scope = User.where.not(id: current_user.id)
      scope = scope.where.not(account_type: "owner") unless current_user.account_owner?
      scope
    end

    def ensure_store_credit_target_manageable!
      return if store_credit_target_manageable?(@user)

      head :not_found
    end

    def store_credit_form_props
      return nil unless allowed_user_action?("store", "store.credit.adjust")
      return nil unless store_credit_target_manageable?(@user)

      {
        action_url: adjust_store_credit_admin_user_path(@user),
        authorization_url: authorize_store_credit_adjustment_admin_user_path(@user),
        balance_cents: @user.store_credit_cents.to_i,
        balance_label: format_money(@user.store_credit_cents.to_i, "CNY")
      }
    end

    def ensure_manageable_target!
      return if manageable_user?(@user)

      redirect_to admin_user_path(@user), alert: t("mcweb.flash.permission_denied")
    end

    def allowed_user_action?(module_key, permission_key)
      current_user.admin_module_allowed?(module_key) && current_user.permission?(permission_key)
    end
  end
end
