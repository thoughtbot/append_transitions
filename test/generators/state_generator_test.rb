# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "rails/generators/test_case"
require "generators/append_transitions/state/state_generator"

class StateGeneratorTest < Rails::Generators::TestCase
  # Namespace for loading generated models, as an app would define them
  module GeneratedModels
    ApplicationRecord = Class.new(ActiveRecord::Base) { self.abstract_class = true }
  end

  tests AppendTransitions::Generators::StateGenerator
  destination Pathname(__dir__).join("../../tmp/generators").expand_path

  setup :prepare_destination

  teardown do
    %i[
      widget_statuses widgets subscription_statuses subscriptions
      admin_user_statuses admin_users
    ].each do |table|
      connection.drop_table table, if_exists: true
    end
    %i[CreateWidgetStatuses CreateSubscriptionStatuses CreateAdminUserStatuses].each do |migration|
      Object.send(:remove_const, migration) if Object.const_defined?(migration)
    end
    %i[UserStatus User].each do |model|
      GeneratedModels.send(:remove_const, model) if GeneratedModels.const_defined?(model, false)
    end
  end

  def test_creates_migration_for_state_table
    run_generator %w[User status]

    assert_migration "db/migrate/create_user_statuses.rb" do |migration|
      assert_includes migration, "class CreateUserStatuses < ActiveRecord::Migration["
      assert_includes migration, "create_table :user_statuses do |t|"
      assert_includes migration,
        "t.references :user, null: false, foreign_key: true, index: false"
      assert_includes migration, "t.string :status, null: false"
      assert_includes migration, "t.timestamps"
      assert_includes migration,
        "add_index :user_statuses, [:user_id, :created_at, :id],\n" \
        "      order: {created_at: :desc, id: :desc}"
    end
  end

  def test_generated_migration_creates_recommended_index
    connection.create_table :widgets
    run_generator %w[Widget status]

    migrate_up "db/migrate/create_widget_statuses.rb"

    connection.indexes(:widget_statuses).sole.tap do |index|
      assert_equal %w[widget_id created_at id], index.columns
      assert_equal({"created_at" => :desc, "id" => :desc}, index.orders)
    end
  end

  def test_generated_migration_names_long_index_before_active_record_7_1
    connection.create_table :subscriptions
    run_generator %w[Subscription status]

    migrate_up "db/migrate/create_subscription_statuses.rb"

    connection.indexes(:subscription_statuses).sole.tap do |index|
      assert_equal %w[subscription_id created_at id], index.columns
    end
  end

  def test_uses_primary_key_type_option
    run_generator %w[User status --primary-key-type=uuid]

    assert_migration "db/migrate/create_user_statuses.rb" do |migration|
      assert_includes migration, "create_table :user_statuses, id: :uuid do |t|"
      assert_includes migration,
        "t.references :user, null: false, foreign_key: true, index: false, type: :uuid"
    end
  end

  def test_uses_primary_key_type_from_app_config
    with_app_primary_key_type(:uuid) do
      run_generator %w[User status]
    end

    assert_migration "db/migrate/create_user_statuses.rb" do |migration|
      assert_includes migration, "create_table :user_statuses, id: :uuid do |t|"
      assert_includes migration, "index: false, type: :uuid"
    end
  end

  def test_generated_migration_references_uuid_primary_key
    connection.create_table :widgets, id: :uuid
    run_generator %w[Widget status --primary-key-type=uuid]

    migrate_up "db/migrate/create_widget_statuses.rb"

    columns = connection.columns(:widget_statuses).index_by(&:name)
    assert_equal :uuid, columns["id"].type
    assert_equal :uuid, columns["widget_id"].type
  end

  def test_writes_migration_to_database_migrations_path
    with_database_migrations_path("animals", "db/animals_migrate") do
      run_generator %w[User status --database=animals]
    end

    assert_migration "db/animals_migrate/create_user_statuses.rb"
  end

  def test_inherits_model_from_database_abstract_class
    run_generator %w[User status --database=animals]

    assert_file "app/models/user_status.rb", /class UserStatus < AnimalsRecord/
  end

  def test_creates_database_abstract_class_when_missing
    run_generator %w[User status --database=animals]

    assert_file "app/models/animals_record.rb" do |abstract_class|
      assert_includes abstract_class, "class AnimalsRecord < ApplicationRecord"
      assert_includes abstract_class, "self.abstract_class = true"
      assert_includes abstract_class, "connects_to database: { writing: :animals }"
    end
  end

  def test_keeps_existing_database_abstract_class
    existing = "class AnimalsRecord < ApplicationRecord\n  # customized\nend\n"
    path = Pathname(destination_root).join("app/models/animals_record.rb")
    path.dirname.mkpath
    path.write(existing)

    run_generator %w[User status --database=animals]

    assert_equal existing, path.read
  end

  def test_creates_read_only_model_for_state_table
    run_generator %w[User status]

    assert_file "app/models/user_status.rb" do |model|
      assert_includes model, "class UserStatus < ApplicationRecord"
      assert_includes model, "belongs_to :user"
      assert_includes model,
        "def readonly? = super || (persisted? && !destroyed_by_association)"
    end
  end

  def test_generated_model_can_only_be_destroyed_through_its_parent
    run_generator %w[User status]
    load_generated_model "app/models/user_status.rb"
    GeneratedModels.const_set(:User, Class.new(GeneratedModels::ApplicationRecord) do
      self.table_name = "users"
      has_many :user_statuses, dependent: :destroy
    end)
    user = GeneratedModels::User.create!
    status = GeneratedModels::UserStatus.create!(user:, status: "pending")

    assert_raises(ActiveRecord::ReadOnlyRecord) { status.destroy }
    user.destroy!

    assert_empty GeneratedModels::UserStatus.where(user_id: user.id)
  end

  def test_names_state_table_after_parent_and_base_name
    run_generator %w[Document review]

    assert_migration "db/migrate/create_document_reviews.rb" do |migration|
      assert_includes migration, "create_table :document_reviews do |t|"
      assert_includes migration, "t.references :document,"
      assert_includes migration,
        "add_index :document_reviews, [:document_id, :created_at, :id],"
    end
    assert_file "app/models/document_review.rb" do |model|
      assert_includes model, "class DocumentReview < ApplicationRecord"
      assert_includes model, "belongs_to :document"
    end
  end

  def test_namespaces_state_model_and_table_like_the_parent
    output = run_generator %w[Admin::User status]

    assert_migration "db/migrate/create_admin_user_statuses.rb" do |migration|
      assert_includes migration, "create_table :admin_user_statuses do |t|"
      assert_includes migration,
        "t.references :user, null: false, foreign_key: {to_table: :admin_users}, index: false"
      assert_includes migration,
        "add_index :admin_user_statuses, [:user_id, :created_at, :id],"
    end
    assert_file "app/models/admin/user_status.rb" do |model|
      assert_includes model, "class Admin::UserStatus < ApplicationRecord"
      assert_includes model, "belongs_to :user"
    end
    assert_includes output, "app/models/admin/user.rb"
    assert_includes output, 'class_name: "Admin::UserStatus",'
  end

  def test_generated_migration_references_namespaced_parent_table
    connection.create_table :admin_users
    run_generator %w[Admin::User status]

    migrate_up "db/migrate/create_admin_user_statuses.rb"

    connection.foreign_keys(:admin_user_statuses).sole.tap do |foreign_key|
      assert_equal "admin_users", foreign_key.to_table
      assert_equal "user_id", foreign_key.column
    end
  end

  def test_names_state_column_after_option
    with_active_record_version("7.1.0") do
      run_generator %w[Document review --state-column=stage]
    end

    assert_migration "db/migrate/create_document_reviews.rb" do |migration|
      assert_includes migration, "t.string :stage, null: false"
      assert_includes migration, "include: :stage"
    end
  end

  def test_prints_has_current_to_add_to_parent
    output = run_generator %w[Document review]

    assert_includes output, "app/models/document.rb"
    assert_includes output, "include AppendTransitions::HasCurrent.new("
    assert_includes output, ":review,"
    assert_includes output, 'class_name: "DocumentReview",'
    refute_includes output, "state_column:"
  end

  def test_prints_state_column_when_not_default
    output = run_generator %w[Document review --state-column=stage]

    assert_includes output, "state_column: :stage,"
  end

  private

  def connection
    ActiveRecord::Base.connection
  end

  def load_generated_model(relative_path)
    GeneratedModels.module_eval(Pathname(destination_root).join(relative_path).read)
  end

  def migrate_up(relative_path)
    path = migration_file_name(Pathname(destination_root).join(relative_path))
    load path

    migration = Pathname(relative_path).basename(".rb").to_s.camelize.constantize.new
    migration.suppress_messages { migration.migrate(:up) }
  end

  def with_active_record_version(version, &block)
    ActiveRecord.stub(:version, Gem::Version.new(version), &block)
  end

  # What config.generators { |g| g.orm :active_record, primary_key_type: }
  # sets in an app
  def with_app_primary_key_type(type)
    generator_options = Rails::Generators.options
    original_options = generator_options.dup
    active_record_options = generator_options[:active_record].to_h
    generator_options[:active_record] = active_record_options.merge(primary_key_type: type)

    yield
  ensure
    generator_options.replace(original_options)
  end

  # Stands in for a Rails app whose database.yml has a second database
  # with its own migrations_paths
  def with_database_migrations_path(name, migrations_paths)
    original_configurations = ActiveRecord::Base.configurations
    ActiveRecord::Base.configurations = {
      "test" => {name => {"adapter" => "postgresql", "migrations_paths" => migrations_paths}}
    }

    with_rails_methods(application: Object.new, env: "test") { yield }
  ensure
    ActiveRecord::Base.configurations = original_configurations
  end

  # Defines Rails.application and the like for the block, restoring any
  # that were already defined
  def with_rails_methods(**values)
    original_methods = values.keys
      .select { |name| Rails.respond_to?(name) }
      .to_h { |name| [name, Rails.method(name)] }
    values.each { |name, value| Rails.define_singleton_method(name) { value } }

    yield
  ensure
    values.each_key { |name| Rails.singleton_class.remove_method(name) }
    original_methods.each { |name, method| Rails.define_singleton_method(name, method) }
  end
end
