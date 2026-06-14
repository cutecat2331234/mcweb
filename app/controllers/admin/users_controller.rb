# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    before_action -> { require_permission("system.settings.manage") }
    before_action :set_user, only: %i[show edit update destroy]

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
      render inertia: "Admin/Generic/Show", props: {
        title: @user.display_name.presence || @user.username,
        subtitle: @user.email,
        fields: [
          { label: "用户名", value: @user.username },
          { label: "状态", value: @user.status },
          { label: "角色", value: @user.roles.pluck(:name).join(", ").presence || "—" },
          { label: "邮箱已验证", value: @user.email_verified? ? "是" : "否" },
          { label: "注册时间", value: l(@user.created_at, format: :long) }
        ],
        backUrl: admin_users_path
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

    private

    def set_user
      @user = User.find_by!(public_id: params[:id])
    end

    def user_params
      params.expect(user: %i[display_name locale time_zone status])[:user]
    end
  end
end
