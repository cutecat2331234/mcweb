# frozen_string_literal: true

module Community
  # Awards (or deducts, for admin adjustments) virtual currency "points" to a
  # user, Discuz/XenForo style. Idempotency is enforced at the DB level so that
  # rule-driven side effects (post created, reaction received, solution accepted)
  # never double-award even if their callers fire twice.
  #
  #   Community::AwardPoints.call(
  #     user: some_user,
  #     amount: 5,
  #     reason: "post_created",
  #     source: post                 # polymorphic; dedupes via unique index
  #   )
  #
  #   Community::AwardPoints.call(
  #     user: post.user,
  #     amount: 2,
  #     reason: "reaction_received",
  #     dedupe_token: "reaction:#{post.id}:#{reactor.id}" # token-based dedupe
  #   )
  #
  # Returns a ServiceResult. Success values:
  #   { skipped: true }   - amount was 0/nil for a rule award (rule disabled)
  #   { duplicate: true } - already awarded for this source/dedupe_token
  #   { account:, transaction:, balance: } - awarded
  class AwardPoints < ApplicationService
    def initialize(user:, amount:, reason:, source: nil, currency: "points", dedupe_token: nil, actor: nil, note: nil)
      @user = user
      @amount = amount.to_i if amount
      @reason = reason.to_s
      @source = source
      @currency = currency.presence || "points"
      @dedupe_token = dedupe_token.presence
      @actor = actor
      @note = note
    end

    def call
      return ServiceResult.failure(error: "point_user_required") if @user.nil?

      # Rule-driven awards pass a configured amount; 0 means "rule disabled" -> skip.
      # admin_adjust is exempt: a 0 admin adjustment is still a no-op we can skip.
      if @amount.nil? || @amount.zero?
        return ServiceResult.success(skipped: true)
      end

      account = find_or_create_account

      tx = nil
      new_balance = nil
      begin
        Community::PointAccount.transaction(requires_new: true) do
          account.lock!
          new_balance = account.balance + @amount

          if new_balance.negative?
            raise InsufficientBalance
          end

          # Insert the transaction FIRST so a duplicate (unique index violation)
          # aborts the whole transaction and leaves the balance untouched.
          tx = Community::PointTransaction.create!(
            account: account,
            user: @user,
            currency: @currency,
            amount: @amount,
            reason: @reason,
            source: @source,
            balance_after: new_balance,
            dedupe_token: @dedupe_token
          )

          account.update!(balance: new_balance)
        end
      rescue InsufficientBalance
        return ServiceResult.failure(error: "point_balance_insufficient")
      rescue ActiveRecord::RecordNotUnique
        # Idempotency hit (source-based index or dedupe_token partial index):
        # treat as already awarded, balance untouched.
        return ServiceResult.success(duplicate: true)
      end

      ServiceResult.success(account: account, transaction: tx, balance: new_balance)
    end

    # Convenience for rule-driven awards: reads the configured amount from
    # SiteSetting and skips automatically when <= 0 (handled in #call).
    def self.for_rule(user:, rule:, source: nil, dedupe_token: nil, default:)
      amount = SiteSetting.get("forum.points.#{rule}", default.to_s).to_i
      call(user: user, amount: amount, reason: rule, source: source, dedupe_token: dedupe_token)
    end

    private

    class InsufficientBalance < StandardError; end

    def find_or_create_account
      Community::PointAccount.find_or_create_by!(user: @user, currency: @currency)
    rescue ActiveRecord::RecordNotUnique
      # Lost a race creating the account; the row now exists.
      Community::PointAccount.find_by!(user: @user, currency: @currency)
    end
  end
end
