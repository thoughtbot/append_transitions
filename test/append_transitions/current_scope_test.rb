# frozen_string_literal: true

require "test_helper"

class CurrentScopeTest < Minitest::Test
  UserStatus = build_user_status_class(self)
  User = build_user_class(UserStatus)
  Admin = Class.new(User)

  Account = Class.new(ActiveRecord::Base) do
    self.table_name = "accounts"
    self.primary_key = "number"
  end
  AccountStatus = Class.new(ActiveRecord::Base) { self.table_name = "account_statuses" }

  LabeledStatus = Class.new(ActiveRecord::Base) { self.table_name = "labeled_statuses" }

  Order = Class.new(ActiveRecord::Base) { self.table_name = "order" }
  OrderStatus = Class.new(ActiveRecord::Base) { self.table_name = "order_statuses" }

  def teardown
    [UserStatus, LabeledStatus, User].each(&:delete_all)
    [AccountStatus, Account].each(&:delete_all)
    [OrderStatus, Order].each(&:delete_all)
  end

  def test_returns_records_with_hydrated_current_status
    time = 2.minutes.from_now.change(usec: 0)
    _user = create_user(statuses: [["pending", time]])

    users = build_scope.call(User).to_a

    assert_equal "pending", users.first.current_status.status
    assert_equal time, users.first.current_status.created_at
  end

  def test_returns_nil_hydration_when_no_states_exist
    _user = create_user

    users = build_scope.call(User).to_a

    assert_nil users.first.current_status
  end

  def test_supports_where_filtering_on_joined_table
    user_b = create_user(statuses: ["denied"])
    _user_a = create_user(statuses: ["approved"])

    results = build_scope.call(User)
      .where(current_status: {status: "denied"})
      .to_a

    assert_equal 1, results.size
    assert_equal user_b.id, results.first.id
  end

  def test_supports_count
    _user_a = create_user(statuses: ["pending"])
    _user_b = create_user

    assert_equal 2, build_scope.call(User).count
  end

  def test_uses_configured_foreign_key
    _user = create_user(statuses: ["pending"])

    assert_raises(ActiveRecord::StatementInvalid) do
      build_scope(foreign_key: :nonexistent).call(User).to_a
    end

    # An existing foreign key should not raise
    build_scope(foreign_key: :user_id).call(User).to_a
  end

  def test_infers_foreign_key_from_base_class_when_not_configured
    user = create_user(statuses: ["pending"])

    results = build_scope(foreign_key: nil).call(User).to_a

    assert_equal user.id, results.first.current_status.user_id
  end

  def test_infers_foreign_key_from_sti_base_class_when_not_configured
    admin = create_user(user_class: Admin, statuses: ["pending"])

    results = build_scope(foreign_key: nil).call(Admin).to_a

    assert_equal admin.id, results.first.current_status.user_id
  end

  def test_uses_configured_attr_name
    _user = create_user(statuses: ["pending"])

    scope = build_scope(attr_name: "current_phase")
    results = scope.call(User).to_a

    assert_equal "pending", results.first.instance_variable_get(:@current_phase).status
    assert_nil results.first.instance_variable_get(:@current_status)
  end

  def test_respects_custom_order
    _user = create_user(statuses: ["first", "second"])

    results = build_scope(order: {id: :asc}).call(User).to_a

    assert_equal 1, results.length
    assert_equal "first", results.first.current_status.status
  end

  def test_joins_on_the_base_primary_key
    account = Account.create!
    AccountStatus.create!(account_number: account.number, status: "pending")
    scope = build_scope(
      class_name: AccountStatus.name,
      foreign_key: :account_number
    )

    result = scope.call(Account).first

    assert_equal "pending", result.instance_variable_get(:@current_status).status
  end

  def test_quotes_the_base_table_name
    order = Order.create!
    OrderStatus.create!(order_id: order.id, status: "pending")
    scope = build_scope(class_name: OrderStatus.name, foreign_key: :order_id)

    result = scope.call(Order).first

    assert_equal "pending", result.instance_variable_get(:@current_status).status
  end

  def test_quotes_state_column_names
    user = create_user
    LabeledStatus.create!(user_id: user.id, status: "pending", Label: "urgent")
    scope = build_scope(class_name: LabeledStatus.name)

    result = scope.call(User).first

    assert_equal "urgent", result.current_status.Label
  end

  private

  def create_user(user_class: User, statuses: [])
    user_class.create!.tap do |user|
      statuses.each do |status, created_at|
        UserStatus.create!(user:, status:, created_at:)
      end
    end
  end

  def build_scope(
    class_name: UserStatus.name, attr_name: "current_status",
    foreign_key: :user_id, order: {created_at: :desc, id: :desc}
  )
    AppendTransitions::CurrentScope.new(
      class_name:,
      attr_name:,
      foreign_key:,
      order:
    )
  end
end
