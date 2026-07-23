# frozen_string_literal: true

module Api
  module V1
    class UsersController < BaseController
      include Serialization

      # GET /api/v1/users/:id  (id = user public_id)
      def show
        user = User.find_by!(public_id: params[:id])
        raise ActiveRecord::RecordNotFound if user.deleted_at.present?

        render json: { data: serialize_user(user) }
      end
    end
  end
end
