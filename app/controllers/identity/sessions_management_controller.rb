# frozen_string_literal: true

module Identity
  class SessionsManagementController < ApplicationController
    before_action :require_login

    def index
      sessions = current_user.sessions.active.order(last_active_at: :desc)

      render inertia: "Identity/SessionsManagement/Index", props: {
        sessions: sessions.map { |session| serialize_session_record(session) }
      }
    end

    def destroy
      session_record = current_user.sessions.find(params[:id])
      revoking_current = session_record.id == current_session&.id
      Identity::SessionManager.call(session: session_record, action: :revoke)

      if revoking_current
        sign_out
        redirect_to identity_sign_in_path, notice: "当前会话已撤销，请重新登录。"
      else
        redirect_to identity_sessions_management_index_path, notice: "会话已撤销。"
      end
    end
  end
end
