# frozen_string_literal: true

require "test_helper"

class IndexValidatorTest < Minitest::Test
  User = Class.new(ActiveRecord::Base) { self.table_name = "users" }
  Admin = Class.new(User)

  attr_reader :model_class

  def setup
    @original_configuration = AppendTransitions.configuration
    AppendTransitions.instance_variable_set(:@configuration, nil)
  end

  def teardown
    AppendTransitions.instance_variable_set(:@configuration, @original_configuration)
    ActiveRecord::Base.connection.drop_table :validator_statuses, if_exists: true

    remove_model_class
  end

  def test_does_not_raise_when_index_exists_and_configured_to_raise
    configure_on_missing_index :raise
    create_table
    add_index :user_id, :created_at, :id

    build_validator(class_name: model_class.name).validate!(User)
  end

  def test_raises_when_index_does_not_exist_and_configured_to_raise
    configure_on_missing_index :raise
    create_table

    error = assert_raises(AppendTransitions::MissingIndexError) do
      build_validator(class_name: model_class.name).validate!(User)
    end

    assert_includes error.message, "validator_statuses"
    assert_includes error.message, "user_id"
    assert_includes error.message,
      "add_index :validator_statuses, [:user_id, :created_at, :id], " \
      "order: {created_at: :desc, id: :desc}"
  end

  def test_does_not_warn_when_index_exists_and_configured_to_warn
    configure_on_missing_index :warn
    create_table
    add_index :user_id, :created_at, :id

    output = capture_io do
      build_validator(class_name: model_class.name).validate!(User)
    end

    assert_empty output[1]
  end

  def test_warns_when_index_does_not_exist_and_configured_to_warn
    configure_on_missing_index :warn
    create_table

    output = capture_io do
      build_validator(class_name: model_class.name).validate!(User)
    end

    assert_includes output[1], "validator_statuses"
    assert_includes output[1], "user_id"
  end

  def test_warns_when_index_does_not_exist_and_not_configured
    create_table

    _out, err = capture_io do
      build_validator(class_name: model_class.name).validate!(User)
    end

    assert_includes err, "validator_statuses"
  end

  def test_only_checks_once_per_instance
    configure_on_missing_index :raise
    create_table
    add_index :user_id, :created_at, :id

    validator = build_validator(class_name: model_class.name)
    validator.validate!(User)

    drop_index :user_id, :created_at, :id

    validator.validate!(User)
  end

  def test_raises_on_invalid_configuration_value
    assert_raises(ArgumentError) do
      configure_on_missing_index :invalid
    end
  end

  def test_raises_when_index_exists_but_foreign_key_is_not_leading
    configure_on_missing_index :raise
    create_table
    add_index :created_at, :user_id

    assert_raises(AppendTransitions::MissingIndexError) do
      build_validator(class_name: model_class.name).validate!(User)
    end
  end

  def test_raises_when_index_has_only_the_foreign_key
    configure_on_missing_index :raise
    create_table
    add_index :user_id

    assert_raises(AppendTransitions::MissingIndexError) do
      build_validator(class_name: model_class.name).validate!(User)
    end
  end

  def test_raises_when_index_is_missing_an_order_column
    configure_on_missing_index :raise
    create_table
    add_index :user_id, :created_at

    assert_raises(AppendTransitions::MissingIndexError) do
      build_validator(
        class_name: model_class.name, order: {created_at: :desc, id: :desc}
      ).validate!(User)
    end
  end

  def test_does_not_raise_when_index_matches_configured_order
    configure_on_missing_index :raise
    create_table
    add_index :user_id, :created_at

    build_validator(
      class_name: model_class.name, order: {created_at: :desc}
    ).validate!(User)
  end

  def test_does_not_raise_when_index_has_extra_trailing_columns
    configure_on_missing_index :raise
    create_table
    add_index :user_id, :created_at, :id, :status, name: "validator_statuses_covering"

    build_validator(class_name: model_class.name).validate!(User)
  end

  def test_raises_when_matching_index_is_partial
    configure_on_missing_index :raise
    create_table
    add_index :user_id, :created_at, :id, where: "status = 'pending'"

    assert_raises(AppendTransitions::MissingIndexError) do
      build_validator(class_name: model_class.name).validate!(User)
    end
  end

  def test_raises_when_only_index_is_an_expression
    configure_on_missing_index :raise
    create_table
    ActiveRecord::Base.connection.execute(
      "CREATE INDEX ON validator_statuses (user_id, (created_at::date), id)"
    )

    assert_raises(AppendTransitions::MissingIndexError) do
      build_validator(class_name: model_class.name).validate!(User)
    end
  end

  def test_infers_foreign_key_from_owner_when_not_configured
    configure_on_missing_index :raise
    create_table

    error = assert_raises(AppendTransitions::MissingIndexError) do
      build_validator(class_name: model_class.name, foreign_key: nil).validate!(User)
    end

    assert_includes error.message, "user_id"

    add_index :user_id, :created_at, :id

    # With an index on the inferred foreign key it should not raise
    build_validator(class_name: model_class.name, foreign_key: nil).validate!(User)
  end

  def test_infers_foreign_key_from_sti_base_class_when_not_configured
    configure_on_missing_index :raise
    create_table
    add_index :user_id, :created_at, :id

    build_validator(class_name: model_class.name, foreign_key: nil).validate!(Admin)
  end

  private

  def create_table
    ActiveRecord::Schema.define do
      create_table :validator_statuses, force: :cascade do |t|
        t.bigint :user_id, null: false
        t.string :status, null: false
        t.timestamps
      end
    end

    define_model_class
  end

  def configure_on_missing_index(value)
    AppendTransitions.configure do |config|
      config.on_missing_index = value
    end
  end

  def add_index(*columns, **options)
    ActiveRecord::Base.connection.add_index(:validator_statuses, columns, **options)
  end

  def drop_index(*columns)
    ActiveRecord::Base.connection.remove_index(
      :validator_statuses, column: columns
    )
  end

  def define_model_class
    @model_class = Class.new(ActiveRecord::Base) do
      self.table_name = "validator_statuses"
    end

    Object.const_set(:ValidatorStatus, @model_class)
  end

  def remove_model_class
    Object.send(:remove_const, :ValidatorStatus) if defined?(::ValidatorStatus)

    @model_class = nil
  end

  def build_validator(
    class_name:,
    foreign_key: :user_id,
    state_column: :status,
    order: {created_at: :desc, id: :desc}
  )
    AppendTransitions::IndexValidator.new(class_name:, foreign_key:, state_column:, order:)
  end
end
