# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class RecommendedIndexTest < Minitest::Test
  def test_includes_state_column_on_active_record_7_1_and_later
    index = build_index(
      table_name: "user_statuses",
      foreign_key: :user_id,
      order: {created_at: :desc, id: :desc},
      state_column: :status
    )

    lines = with_active_record_version("7.1.0") { index.lines }

    assert_equal [
      "add_index :user_statuses, [:user_id, :created_at, :id],",
      "order: {created_at: :desc, id: :desc},",
      "include: :status"
    ], lines
  end

  def test_omits_state_column_before_active_record_7_1
    index = build_index(
      table_name: "user_statuses",
      foreign_key: :user_id,
      order: {created_at: :desc, id: :desc},
      state_column: :status
    )

    lines = with_active_record_version("7.0.8") { index.lines }

    assert_equal [
      "add_index :user_statuses, [:user_id, :created_at, :id],",
      "order: {created_at: :desc, id: :desc}"
    ], lines
  end

  def test_uses_configured_names_and_order
    index = build_index(
      table_name: "document_reviews",
      foreign_key: :document_number,
      order: {position: :asc},
      state_column: :stage
    )

    lines = with_active_record_version("7.1.0") { index.lines }

    assert_equal [
      "add_index :document_reviews, [:document_number, :position],",
      "order: {position: :asc},",
      "include: :stage"
    ], lines
  end

  def test_names_index_before_active_record_7_1_when_default_name_is_too_long
    index = build_index(
      table_name: "subscription_statuses",
      foreign_key: :subscription_id,
      order: {created_at: :desc, id: :desc},
      state_column: :status
    )

    lines = with_active_record_version("7.0.8") { index.lines }

    assert_equal [
      "add_index :subscription_statuses, [:subscription_id, :created_at, :id],",
      "order: {created_at: :desc, id: :desc},",
      'name: "index_subscription_statuses_current"'
    ], lines
  end

  def test_does_not_name_index_on_active_record_7_1_and_later
    index = build_index(
      table_name: "subscription_statuses",
      foreign_key: :subscription_id,
      order: {created_at: :desc, id: :desc},
      state_column: :status
    )

    lines = with_active_record_version("7.1.0") { index.lines }

    assert_equal [
      "add_index :subscription_statuses, [:subscription_id, :created_at, :id],",
      "order: {created_at: :desc, id: :desc},",
      "include: :status"
    ], lines
  end

  def test_columns_are_foreign_key_followed_by_order_columns
    index = build_index(
      table_name: "user_statuses",
      foreign_key: "user_id",
      order: {"created_at" => :desc, :id => :desc},
      state_column: :status
    )

    columns = index.columns

    assert_equal [:user_id, :created_at, :id], columns
  end

  private

  def build_index(table_name:, foreign_key:, order:, state_column:)
    AppendTransitions::RecommendedIndex.new(
      table_name:, foreign_key:, order:, state_column:
    )
  end

  def with_active_record_version(version, &block)
    ActiveRecord.stub(:version, Gem::Version.new(version), &block)
  end
end
