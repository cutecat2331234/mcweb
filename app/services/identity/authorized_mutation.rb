# frozen_string_literal: true

module Identity
  # Runs a permission-dependent mutation under the shared side of the
  # permission barrier. The actor is always reloaded after acquiring the lock,
  # so an object cached earlier in the request is never treated as an
  # authorization snapshot.
  class AuthorizedMutation
    class << self
      def with(actor:, all_of: [], any_of: [], failure_code: "forbidden", &block)
        new(
          actor:,
          all_of:,
          any_of:,
          failure_code:
        ).with(&block)
      end
    end

    def initialize(actor:, all_of:, any_of:, failure_code:)
      @actor_id = actor&.id
      @all_of = normalize_permissions(all_of)
      @any_of = normalize_permissions(any_of)
      @failure_code = failure_code.to_s.presence || "forbidden"
    end

    def with
      PermissionMutationLock.with_shared do
        actor = User.uncached { User.find_by(id: @actor_id) }
        return failure unless authorized?(actor)

        yield actor
      end
    end

    private

    def normalize_permissions(values)
      Array(values).map(&:to_s).reject(&:blank?).uniq.freeze
    end

    def authorized?(actor)
      return false unless actor&.session_eligible?
      return false unless @all_of.all? { |permission| actor.permission?(permission) }

      @any_of.empty? || @any_of.any? { |permission| actor.permission?(permission) }
    end

    def failure
      ServiceResult.failure(error: @failure_code, code: @failure_code)
    end
  end
end
