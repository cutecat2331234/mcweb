# frozen_string_literal: true

require "test_helper"

module Commerce
  class StoreCreditLedgerPageTest < ActiveSupport::TestCase
    setup do
      @user = create_user
      @recorded_at = Time.zone.parse("2026-09-04 09:00:00 UTC")

      balance = 1_000
      57.times do |index|
        amount = index.even? ? 100 : -50
        Commerce::StoreCreditTransaction.create!(
          user: @user,
          amount_cents: amount,
          balance_before_cents: balance,
          balance_after_cents: balance + amount,
          note: "ledger-#{index}",
          created_at: @recorded_at + index.seconds,
          updated_at: @recorded_at + index.seconds
        )
        balance += amount
      end
    end

    test "stable cursor reaches the complete ledger without duplicates" do
      first = Commerce::StoreCreditLedgerPage.call(user: @user)

      assert_predicate first, :success?
      assert_equal Commerce::StoreCreditLedgerPage::PAGE_SIZE, first.value.fetch(:transactions).length
      assert_equal true, first.value.dig(:pagination, :has_more)
      cursor = first.value.dig(:pagination, :next_cursor)
      assert cursor.present?

      Commerce::StoreCreditTransaction.create!(
        user: @user,
        amount_cents: 25,
        balance_before_cents: 2_500,
        balance_after_cents: 2_525,
        note: "newer-entry-after-page-one",
        created_at: @recorded_at + 1.day,
        updated_at: @recorded_at + 1.day
      )

      second = Commerce::StoreCreditLedgerPage.call(user: @user, cursor: cursor)
      assert_predicate second, :success?
      assert_equal 7, second.value.fetch(:transactions).length
      assert_equal false, second.value.dig(:pagination, :has_more)

      ids = first.value.fetch(:transactions).map(&:id) + second.value.fetch(:transactions).map(&:id)
      assert_equal 57, ids.length
      assert_equal 57, ids.uniq.length
      assert_equal(
        Commerce::StoreCreditTransaction
          .where(user: @user)
          .where.not(note: "newer-entry-after-page-one")
          .order(created_at: :desc, id: :desc)
          .pluck(:id),
        ids
      )
    end

    test "timestamp ties cross the cursor boundary in deterministic id order" do
      tied_user = create_user
      tied_at = @recorded_at + 1.day
      52.times do |index|
        Commerce::StoreCreditTransaction.create!(
          user: tied_user,
          amount_cents: 1,
          balance_before_cents: index,
          balance_after_cents: index + 1,
          note: "tied-ledger-#{index}",
          created_at: tied_at,
          updated_at: tied_at
        )
      end

      first = Commerce::StoreCreditLedgerPage.call(user: tied_user)
      second = Commerce::StoreCreditLedgerPage.call(
        user: tied_user,
        cursor: first.value.dig(:pagination, :next_cursor)
      )
      ids = first.value.fetch(:transactions).map(&:id) +
        second.value.fetch(:transactions).map(&:id)

      assert_equal 52, ids.length
      assert_equal ids.sort.reverse, ids
      assert_equal 52, ids.uniq.length
    end

    test "cursor is signed and scoped to its ledger owner" do
      first = Commerce::StoreCreditLedgerPage.call(user: @user)
      cursor = first.value.dig(:pagination, :next_cursor)
      other = create_user

      assert_predicate Commerce::StoreCreditLedgerPage.call(user: other, cursor: cursor), :failure?
      assert_predicate Commerce::StoreCreditLedgerPage.call(user: @user, cursor: "#{cursor}tampered"), :failure?
    end

    test "new ledger rows require current-version arithmetic snapshots" do
      missing_snapshot = Commerce::StoreCreditTransaction.new(user: @user, amount_cents: 100)
      assert_not missing_snapshot.valid?
      assert missing_snapshot.errors.of_kind?(:balance_before_cents, :invalid)

      current_entry = Commerce::StoreCreditTransaction.new(
        user: @user,
        amount_cents: -100,
        balance_before_cents: 500,
        balance_after_cents: 400
      )
      assert_predicate current_entry, :valid?

      wrong_arithmetic = Commerce::StoreCreditTransaction.new(
        user: @user,
        amount_cents: 100,
        balance_before_cents: 500,
        balance_after_cents: 700
      )
      assert_not wrong_arithmetic.valid?
      assert wrong_arithmetic.errors.of_kind?(:balance_after_cents, :invalid)

      legacy = Commerce::StoreCreditTransaction.new(
        user: @user,
        ledger_version: Commerce::StoreCreditTransaction::LEGACY_LEDGER_VERSION,
        amount_cents: 100
      )
      assert_not legacy.valid?
      assert legacy.errors.of_kind?(:ledger_version, :invalid)
    end

    test "database upgrades a rolling old-writer insert to the current snapshot contract" do
      Commerce::StoreCreditTransaction.insert_all!([
        {
          user_id: @user.id,
          amount_cents: -100,
          note: "rolling-old-writer",
          created_at: Time.current,
          updated_at: Time.current
        }
      ])

      entry = Commerce::StoreCreditTransaction.find_by!(
        user: @user,
        note: "rolling-old-writer"
      )
      assert_equal Commerce::StoreCreditTransaction::CURRENT_LEDGER_VERSION,
        entry.ledger_version
      assert_equal 100, entry.balance_before_cents
      assert_equal 0, entry.balance_after_cents
    end

    test "ledger rows reject model and direct database mutation" do
      entry = Commerce::StoreCreditTransaction.create!(
        user: @user,
        amount_cents: 100,
        balance_before_cents: 2_500,
        balance_after_cents: 2_600,
        note: "append-only"
      )

      assert_not entry.update(note: "rewritten")
      assert entry.errors.of_kind?(:base, :immutable)
      assert_not entry.destroy
      assert entry.errors.of_kind?(:base, :immutable)

      assert_raises ActiveRecord::StatementInvalid do
        Commerce::StoreCreditTransaction.transaction(requires_new: true) do
          Commerce::StoreCreditTransaction.where(id: entry.id).update_all(note: "rewritten")
        end
      end
      assert_raises ActiveRecord::StatementInvalid do
        Commerce::StoreCreditTransaction.transaction(requires_new: true) do
          Commerce::StoreCreditTransaction.where(id: entry.id).delete_all
        end
      end
      assert_equal "append-only", entry.reload.note
    end
  end
end
