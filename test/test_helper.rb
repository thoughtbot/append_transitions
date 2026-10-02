# frozen_string_literal: true

require "minitest/autorun"
require "active_record"
require "active_support/testing/assertions"
require "append_transitions"
require_relative "support/helpers"

Minitest::Test.extend AppendTransitions::TestHelpers
Minitest::Test.include AppendTransitions::TestHelpers

ActiveRecord::Base.establish_connection(
  adapter: "postgresql",
  database: "append_transitions_test"
)

ActiveRecord::Schema.define do
  create_table :organizations, force: :cascade

  create_table :users, force: :cascade do |t|
    t.string :type
    t.references :organization
  end

  create_table :user_statuses, force: :cascade do |t|
    t.references :user, null: false, foreign_key: true, index: false
    t.string :status, null: false
    t.timestamps
    t.index [:user_id, :created_at, :id], order: {created_at: :desc, id: :desc}
  end

  create_table :labeled_statuses, force: :cascade do |t|
    t.references :user, null: false, foreign_key: true, index: false
    t.string :status, null: false
    t.string :Label
    t.timestamps
  end

  create_table :accounts, primary_key: :number, force: :cascade

  create_table :account_statuses, force: :cascade do |t|
    t.bigint :account_number, null: false
    t.foreign_key :accounts, column: :account_number, primary_key: :number
    t.string :status, null: false
    t.timestamps
  end

  create_table :order, force: :cascade

  create_table :order_statuses, force: :cascade do |t|
    t.references :order, null: false, foreign_key: {to_table: :order}
    t.string :status, null: false
    t.timestamps
  end
end
