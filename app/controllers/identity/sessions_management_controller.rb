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
      Identity::SessionManager.call(session: session_record, action: :revoke)
      redirect_to identity_sessions_management_index_path, notice: "Session revoked."
    end
  end
end
