# frozen_string_literal: true

module Community
  module SystemActor
    module_function

    def user
      User.where(status: :active).order(:id).first
    end
  end
end
