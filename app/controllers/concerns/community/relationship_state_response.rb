# frozen_string_literal: true

module Community
  module RelationshipStateResponse
    private

    def render_relationship_state(result)
      response.set_header("Cache-Control", "private, no-store")
      if result.success?
        render json: { data: result.value }
      else
        status = case result.code
        when "conflict" then :conflict
        when "precondition_required" then 428
        else :unprocessable_entity
        end
        render json: { error: result.code || "unprocessable", message: service_error_message(result), data: result.value }, status: status
      end
    end
  end
end
