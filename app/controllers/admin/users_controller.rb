# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    before_action -> { require_permission("system.settings.manage") }
    before_action :set_user, only: %i[show edit update destroy]

    def index
      @users = User.order(created_at: :desc)
    end

    def show
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
