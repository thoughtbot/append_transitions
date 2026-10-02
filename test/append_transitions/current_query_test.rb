# frozen_string_literal: true

require "test_helper"

class CurrentQueryTest < Minitest::Test
  UserStatus = build_user_status_class(self)
  User = build_user_class(UserStatus)
  Admin = Class.new(User)

  def teardown
    [UserStatus, User].each(&:delete_all)
  end

  def test_returns_nil_when_no_records_exist
    user = User.create!
    query = build_query

    result = query.call(user)

    assert_nil result
  end

  def test_returns_the_most_recent_record_by_created_at
    user = create_user(statuses: [
      ["approved", Time.current],
      ["pending", 1.minute.ago]
    ])
    query = build_query(order: {created_at: :desc})

    result = query.call(user)

    assert_equal "approved", result.status
  end

  def test_uses_configured_foreign_key
    user = create_user(statuses: ["pending"])
    query = build_query(foreign_key: :nonexistent)

    assert_raises(ActiveRecord::StatementInvalid) do
      query.call(user)
    end

    query = build_query(foreign_key: :user_id)

    # An existing foreign key should not raise
    query.call(user)
  end

  def test_infers_foreign_key_from_record_class_when_not_configured
    user = create_user(statuses: [["pending", Time.current]])
    _other_user = create_user(statuses: [["approved", Time.current]])

    result = build_query(foreign_key: nil).call(user)

    assert_equal "pending", result.status
  end

  def test_infers_foreign_key_from_sti_base_class_when_not_configured
    admin = create_user(user_class: Admin, statuses: [["pending", Time.current]])

    result = build_query(foreign_key: nil).call(admin)

    assert_equal "pending", result.status
  end

  def test_uses_id_as_tiebreaker_when_created_at_matches
    now = Time.now
    user = create_user(statuses: [["pending", now], ["approved", now]])
    query = build_query(order: {created_at: :desc, id: :desc})

    result = query.call(user)

    assert_equal "approved", result.status
  end

  private

  def create_user(user_class: User, statuses: [])
    user_class.create!.tap do |user|
      statuses.each do |status, created_at|
        UserStatus.create!(user:, status:, created_at:)
      end
    end
  end

  def build_query(order: {created_at: :desc, id: :desc}, foreign_key: :user_id)
    class_name = UserStatus.name

    AppendTransitions::CurrentQuery.new(class_name:, order:, foreign_key:)
  end
end
