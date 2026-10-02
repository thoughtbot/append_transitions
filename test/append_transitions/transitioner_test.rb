# frozen_string_literal: true

require "test_helper"

class TransitionerTest < Minitest::Test
  include ActiveSupport::Testing::Assertions

  UserStatus = build_user_status_class(self)
  User = build_user_class(UserStatus)
  Admin = Class.new(User)
  UntimedStatus = Class.new(ActiveRecord::Base) { self.table_name = "untimed_statuses" }
  HiddenUser = Class.new(ActiveRecord::Base) do
    self.table_name = "users"

    default_scope { where(id: nil) }
  end

  def teardown
    [UserStatus, User].each(&:delete_all)
  end

  def test_inserts_and_returns_new_status_record
    user = create_user

    result = assert_changes(-> { UserStatus.count }, from: 0, to: 1) do
      call_transitioner(user:)
    end

    assert_equal "pending", result.status
  end

  def test_valid_transition_from_existing_status
    user = create_user(statuses: ["pending"])

    result = call_transitioner(
      user:,
      to_state: :approved,
      initial_state: :pending,
      transitions: {pending: :approved}
    )

    assert_equal "approved", result.status
  end

  def test_raises_on_invalid_transition
    user = create_user(statuses: ["approved"])

    error = assert_raises(AppendTransitions::InvalidTransition) do
      call_transitioner(
        user:,
        to_state: :denied,
        initial_state: :approved,
        transitions: {}
      )
    end

    assert_equal "Cannot transition from approved to denied", error.message
  end

  def test_does_not_insert_on_invalid_transition
    user = create_user(statuses: ["approved"])

    assert_no_changes(-> { UserStatus.count }) do
      call_transitioner(
        user:,
        to_state: :denied,
        initial_state: :approved,
        transitions: {}
      )
    rescue AppendTransitions::InvalidTransition
      # Ignore invalid transition, test does not care
    end
  end

  def test_calls_block
    user = create_user
    called = false

    call_transitioner(user:) do
      called = true
    end

    assert called
  end

  def test_block_receives_the_inserted_record
    user = create_user
    received = nil

    result = call_transitioner(user:) do |record|
      received = record
    end

    assert_equal result, received
  end

  def test_does_not_run_block_on_invalid_transition
    user = create_user(statuses: ["approved"])
    called = false

    begin
      call_transitioner(
        user:,
        to_state: :denied,
        initial_state: :approved,
        transitions: {}
      ) do
        called = true
      end
    rescue AppendTransitions::InvalidTransition
      # Ignore invalid transition, test does not care
    end

    refute called
  end

  def test_rolls_back_on_block_error
    user = create_user

    assert_raises(RuntimeError) do
      call_transitioner(user:) do
        raise "side effect failed"
      end
    end

    assert_equal 0, UserStatus.where(user:).count
  end

  def test_serializes_concurrent_transitions
    user = create_user(statuses: ["pending"])
    errors = Queue.new
    status_scope = UserStatus.where(user:)

    2.times.map do
      Thread.new do
        call_transitioner(
          user:,
          to_state: :approved,
          initial_state: :pending,
          transitions: {pending: :approved}
        )
      rescue AppendTransitions::InvalidTransition => e
        errors << e
      end
    end.each(&:join)

    assert_equal 1, errors.size
    assert_equal 2, status_scope.count
    assert_equal ["pending", "approved"], status_scope.map(&:status)
  end

  def test_raises_when_record_is_not_saved
    user = User.new

    error = assert_raises(ActiveRecord::RecordNotSaved) do
      call_transitioner(user:)
    end

    assert_equal "Cannot transition a new record, save it first", error.message
  end

  def test_raises_on_transition_to_nil
    user = create_user(statuses: ["pending"])

    error = assert_raises(AppendTransitions::InvalidTransition) do
      call_transitioner(user:, to_state: nil)
    end

    assert_equal "Cannot transition from pending to nil", error.message
  end

  def test_keeps_unsaved_changes_on_the_record
    user = create_user
    user.type = "Admin"

    call_transitioner(user:)

    assert_equal "Admin", user.type
    assert user.type_changed?
  end

  def test_locks_record_hidden_by_default_scope
    user = HiddenUser.unscoped.create!

    result = call_transitioner(user:)

    assert_equal "pending", result.status
  end

  def test_orders_new_status_after_current_one_when_its_clock_is_ahead
    user = create_user
    _current = UserStatus.create!(user:, status: "pending", created_at: 1.minute.from_now)

    call_transitioner(
      user:,
      to_state: :approved,
      initial_state: :pending,
      transitions: {pending: :approved}
    )

    latest = UserStatus.where(user:).order(created_at: :desc, id: :desc).first
    assert_equal "approved", latest.status
  end

  def test_inserts_into_state_table_without_timestamps
    ActiveRecord::Base.connection.create_table :untimed_statuses, force: true do |t|
      t.bigint :user_id, null: false
      t.string :status, null: false
    end
    user = create_user
    UntimedStatus.create!(user_id: user.id, status: "pending")

    result = call_transitioner(
      user:,
      class_name: UntimedStatus.name,
      order: {id: :desc},
      to_state: :approved,
      initial_state: :pending,
      transitions: {pending: :approved}
    )

    assert_equal "approved", result.status
  ensure
    ActiveRecord::Base.connection.drop_table :untimed_statuses, if_exists: true
  end

  def test_uses_configured_foreign_key
    user = create_user

    assert_raises(ActiveModel::UnknownAttributeError) do
      call_transitioner(user:, foreign_key: :nonexistent)
    end

    # An existing foreign key should not raise
    call_transitioner(user:, foreign_key: :user_id)
  end

  def test_infers_foreign_key_from_record_class_when_not_configured
    user = create_user

    result = call_transitioner(user:, foreign_key: nil)

    assert_equal user.id, result.user_id
  end

  def test_infers_foreign_key_from_sti_base_class_when_not_configured
    admin = create_user(user_class: Admin)

    result = call_transitioner(user: admin, foreign_key: nil)

    assert_equal admin.id, result.user_id
  end

  def test_uses_configured_state_column
    user = create_user

    assert_raises(ActiveModel::UnknownAttributeError) do
      call_transitioner(user:, state_column: :nonexistent)
    end

    # An existing state column should not raise
    call_transitioner(user:, state_column: :status)
  end

  private

  def create_user(user_class: User, statuses: [])
    user_class.create!.tap do |user|
      statuses.each { |status| UserStatus.create!(user:, status:) }
    end
  end

  def call_transitioner(
    user:,
    class_name: UserStatus.name,
    order: {created_at: :desc, id: :desc},
    to_state: :pending,
    initial_state: :pending,
    transitions: {
      pending: [:approved, :denied],
      denied: :pending
    },
    foreign_key: :user_id,
    state_column: :status,
    &block
  )
    transitioner = build_transitioner(
      class_name:, order:, initial_state:, transitions:, foreign_key:, state_column:
    )
    transitioner.call(user, to_state, &block)
  end

  def build_transitioner(
    class_name:, order:, initial_state:, transitions:, foreign_key:, state_column:
  )
    transition_map = AppendTransitions::TransitionMap.new(
      initial_state:,
      transitions:
    )

    current_query = AppendTransitions::CurrentQuery.new(
      class_name:,
      order:,
      foreign_key: :user_id
    )

    AppendTransitions::Transitioner.new(
      class_name:,
      foreign_key:,
      state_column:,
      transition_map:,
      current_query:
    )
  end
end
