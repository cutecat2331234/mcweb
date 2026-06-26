# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      token = cookies.signed[:session_token]
      reject_unauthorized_connection if token.blank?

      record = ::Session.find_by(token_digest: ::Session.digest_token(token))
      user = record&.user
      if record&.active? && user && !user.deleted? && !user.banned?
        user
      else
        reject_unauthorized_connection
      end
    end
  end
end
