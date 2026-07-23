# frozen_string_literal: true

module Api
  module V1
    # Returns the profile of the user the API key acts as. Requires a key bound to
    # a user; keyless/guest keys get 403.
    class MeController < BaseController
      include Serialization

      def show
        return render_error("no_bound_user", status: :forbidden) unless api_user

        render json: {
          data: serialize_user(api_user).merge(
            email: api_user.email,
            account_type: api_user.account_type,
            locale: api_user.locale,
            trust_level: Community::TrustLevel.level_for(api_user)
          )
        }
      end
    end
  end
end
