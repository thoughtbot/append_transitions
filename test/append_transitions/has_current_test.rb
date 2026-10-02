# frozen_string_literal: true

require "test_helper"

class HasCurrentTest < Minitest::Test
  include ActiveSupport::Testing::Assertions

  UserStatus = build_user_status_class(self)
  User = build_user_class(
    UserStatus,
    foreign_key: :user_id,
    initial_state: :processing,
    transitions: {processing: :processed}
  )

  Organization = Class.new(ActiveRecord::Base) do
    self.table_name = "organizations"

    has_many :users_with_status, -> { with_current_status },
      class_name: "HasCurrentTest::User", inverse_of: :organization
  end
  User.belongs_to :organization, optional: true,
    class_name: "HasCurrentTest::Organization", inverse_of: :users_with_status

  # Inferring the foreign key needs a class name, so these can't be
  # built anonymously inside the tests.
  module NilForeignKey
    extend AppendTransitions::TestHelpers

    User = build_user_class(UserStatus, foreign_key: nil, initial_state: :processing)
    Admin = Class.new(User)
  end

  def setup
    @original_on_missing_index = AppendTransitions.configuration.on_missing_index
  end

  def teardown
    AppendTransitions.configuration.on_missing_index = @original_on_missing_index
    [UserStatus, User, Organization].each(&:delete_all)
  end

  def test_current_status_returns_nil_when_no_statuses_exist
    user = create_user

    assert_nil user.current_status
  end

  def test_current_status_returns_the_most_recent_status
    user = create_user(statuses: [
      ["processed", Time.current],
      ["processing", 1.minute.ago]
    ])

    assert_equal "processed", user.current_status.status
  end

  def test_current_status_uses_id_as_tiebreaker_by_default
    created_at = Time.current
    user = create_user(statuses: [
      ["processing", created_at],
      ["processed", created_at]
    ])

    assert_equal "processed", user.current_status.status
  end

  def test_current_status_returns_already_hydrated_value
    user = create_user(statuses: ["processing"])
    hydrated = UserStatus.new(status: "hydrated")
    user.instance_variable_set(:@current_status, hydrated)

    assert_equal "hydrated", user.current_status.status
  end

  def test_current_status_queries_once_across_reads
    user = create_user(statuses: ["processing"])

    queries = count_queries do
      2.times { user.current_status }
    end

    assert_equal 1, queries
  end

  def test_current_status_queries_once_across_reads_when_no_statuses_exist
    user = create_user

    queries = count_queries do
      2.times { user.current_status }
    end

    assert_equal 1, queries
  end

  def test_current_status_is_refreshed_after_transition_status
    user = create_user(statuses: ["processing"])
    user.current_status

    user.transition_status(:processed)

    assert_equal "processed", user.current_status.status
  end

  def test_current_status_is_refreshed_after_reload
    user = create_user(statuses: ["processing"])
    user.current_status
    User.find(user.id).transition_status(:processed)

    user.reload

    assert_equal "processed", user.current_status.status
  end

  def test_current_status_is_refreshed_after_transition_status_when_hydrated
    user = create_user(statuses: ["processing"])
    loaded = User.with_current_status.find(user.id)

    loaded.transition_status(:processed)

    assert_equal "processed", loaded.current_status.status
  end

  def test_current_status_is_refreshed_after_reload_when_hydrated
    user = create_user(statuses: ["processing"])
    loaded = User.with_current_status.find(user.id)
    user.transition_status(:processed)

    loaded.reload

    assert_equal "processed", loaded.current_status.status
  end

  def test_current_status_raises_when_index_is_missing_and_configured_to_raise
    configure_on_missing_index :raise
    user_class = build_user_class(UserStatus, foreign_key: :nonexistent)
    user = create_user(user_class:)

    assert_raises(AppendTransitions::MissingIndexError) do
      user.current_status
    end
  end

  def test_with_current_status_raises_when_index_is_missing_and_configured_to_raise
    configure_on_missing_index :raise
    user_class = build_user_class(UserStatus, foreign_key: :nonexistent)

    assert_raises(AppendTransitions::MissingIndexError) do
      user_class.with_current_status.to_a
    end
  end

  def test_infers_foreign_key_from_owner_name_when_not_configured
    configure_on_missing_index :raise
    user_class = NilForeignKey::User
    user = create_user(user_class:)

    status = user.transition_status(:processing)

    assert_equal user.id, status.user_id
    assert_equal status, user.current_status
    assert_equal status, user_class.with_current_status.first.current_status
  end

  def test_infers_foreign_key_from_sti_base_class_when_not_configured
    configure_on_missing_index :raise
    admin_class = NilForeignKey::Admin
    admin = create_user(user_class: admin_class)

    status = admin.transition_status(:processing)

    assert_equal admin.id, status.user_id
    assert_equal status, admin.current_status
    assert_equal status, admin_class.with_current_status.first.current_status
  end

  def test_uses_configured_foreign_key
    configure_on_missing_index :warn
    user_class = build_user_class(UserStatus, foreign_key: :nonexistent)
    user = create_user(user_class:, statuses: ["pending"])

    _out, err = capture_io do
      assert_raises(ActiveRecord::StatementInvalid) { user.current_status }
      assert_raises(ActiveRecord::StatementInvalid) { user.transition_status(:approved) }
      assert_raises(ActiveRecord::StatementInvalid) { user_class.with_current_status.to_a }
    end

    assert_includes err, "starting with (nonexistent, created_at, id)"

    user_class = build_user_class(UserStatus, foreign_key: :user_id)
    user = user_class.find(user.id)

    # An existing foreign key should not raise
    user.current_status
    user.transition_status(:approved)
    user_class.with_current_status.to_a
  end

  def test_uses_configured_state_column
    configure_on_missing_index :raise
    user_class = build_user_class(UserStatus, foreign_key: :user_id, state_column: :nonexistent)
    user = create_user(user_class:)

    assert_raises(ActiveModel::UnknownAttributeError) do
      user.transition_status(:pending)
    end

    user_class = build_user_class(UserStatus, foreign_key: :user_id, state_column: :status)
    user = user_class.find(user.id)

    # An existing state column should not raise
    user.transition_status(:pending)
  end

  def test_uses_configured_order
    configure_on_missing_index :raise
    user_class = build_user_class(UserStatus, foreign_key: :user_id, order: {created_at: :asc})
    user = create_user(user_class:, statuses: [
      ["pending", 1.minute.ago],
      ["approved", Time.current]
    ])

    assert_equal "pending", user.current_status.status
    assert_equal "pending", user_class.with_current_status.first.current_status.status
  end

  def test_raises_when_order_is_not_a_hash
    error = assert_raises(ArgumentError) do
      build_user_class(UserStatus, foreign_key: :user_id, order: "created_at DESC")
    end

    assert_includes error.message, '"created_at DESC"'
  end

  def test_uses_base_name_for_method_and_attribute_names
    configure_on_missing_index :raise
    user_class = build_user_class(UserStatus, foreign_key: :user_id, base_name: :review)
    user = create_user(user_class:)

    user.transition_review(:pending)
    loaded = user_class.with_current_review.first

    assert_equal "pending", user.current_review.status
    assert_equal "pending", loaded.instance_variable_get(:@current_review).status
    assert_nil loaded.instance_variable_get(:@current_status)
    refute_respond_to user, :current_status
    refute_respond_to user, :transition_status
    refute_respond_to user_class, :with_current_status
  end

  def test_transition_status_inserts_and_returns_record
    user = create_user(statuses: ["processing"])

    result = user.transition_status(:processed)

    assert_equal "processed", result.status
    assert_equal "processed", user.current_status.status
  end

  def test_transition_status_raises_and_does_not_insert_on_invalid_transition
    user = create_user(statuses: ["processed"])

    assert_no_changes(-> { UserStatus.count }) do
      assert_raises(AppendTransitions::InvalidTransition) do
        user.transition_status(:processing)
      end
    end
  end

  def test_transition_status_yields_the_inserted_record
    user = create_user
    received = nil

    result = user.transition_status(:processing) do |record|
      received = record
    end

    assert_equal result, received
  end

  def test_with_current_status_hydrates_the_most_recent_status_per_user
    user_a = create_user(statuses: [
      ["processed", Time.current],
      ["processing", 1.minute.ago]
    ])
    user_b = create_user
    user_c = create_user(statuses: ["processing"])

    loaded = User.with_current_status.index_by(&:id)

    assert_equal "processed", loaded[user_a.id].current_status.status
    assert_nil loaded[user_b.id].current_status
    assert_equal "processing", loaded[user_c.id].current_status.status
  end

  def test_with_current_status_returns_nil_when_no_statuses_exist
    _user = create_user

    loaded = User.with_current_status.to_a

    assert_nil loaded.first.current_status
  end

  def test_with_current_status_does_not_query_again_when_no_statuses_exist
    3.times { create_user }
    loaded = User.with_current_status.to_a

    queries = count_queries do
      loaded.each(&:current_status)
    end

    assert_equal 0, queries
  end

  def test_with_current_status_keeps_state_when_iterated_again_after_transition
    user = create_user(statuses: ["processing"])
    relation = User.with_current_status.where(id: user.id)
    relation.each { |loaded| loaded.transition_status(:processed) }

    current_status = relation.to_a.first.current_status

    assert_equal "processed", current_status.status
  end

  def test_with_current_status_queries_when_state_columns_are_not_selected
    user = create_user(statuses: ["processing"])

    loaded = User.with_current_status.reselect(:id).find(user.id)

    assert_equal "processing", loaded.current_status.status
  end

  def test_with_current_status_sets_inverse_when_preloaded
    organization = Organization.create!
    _user = User.create!(organization:)
    loaded = Organization.includes(:users_with_status).find(organization.id)

    queries = count_queries do
      loaded.users_with_status.first.organization
    end

    assert_equal 0, queries
  end

  def test_with_current_status_can_be_chained_after_where
    _user_a = create_user(statuses: ["processing"])
    user_b = create_user(statuses: ["processed"])

    results = User.where(id: user_b.id).with_current_status.to_a

    assert_equal [user_b.id], results.map(&:id)
    assert_equal "processed", results.first.current_status.status
  end

  def test_with_current_status_supports_where_filtering
    _user_a = create_user(statuses: ["processing"])
    user_b = create_user(statuses: ["processed"])

    results = User.with_current_status
      .where(current_status: {status: "processed"})
      .to_a

    assert_equal 1, results.size
    assert_equal user_b.id, results.first.id
  end

  def test_with_current_status_hydrates_full_ar_objects
    user = create_user
    status = UserStatus.create!(user_id: user.id, status: "processing")

    loaded = User.with_current_status.to_a
    hydrated = loaded.first.current_status

    assert_instance_of UserStatus, hydrated
    assert_equal status.id, hydrated.id
    assert_predicate hydrated, :persisted?
    refute_predicate hydrated, :changed?
  end

  def test_inspect_includes_base_name
    has_current = build_has_current(:status)

    assert_equal "HasCurrent(:status)", has_current.inspect
  end

  private

  def configure_on_missing_index(value)
    AppendTransitions.configuration.on_missing_index = value
  end

  def build_has_current(base_name)
    AppendTransitions::HasCurrent.new(
      base_name,
      class_name: UserStatus.name,
      initial_state: :pending
    )
  end

  def create_user(user_class: User, statuses: [])
    user_class.create!.tap do |user|
      statuses.each do |status, created_at|
        UserStatus.create!(user_id: user.id, status:, created_at:)
      end
    end
  end
end
