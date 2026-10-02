# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"
require "append_transitions"

module AppendTransitions
  module Generators
    # bin/rails generate append_transitions:state User status
    #
    # Creates the user_statuses migration, with the index current_status
    # reads through, and a read-only UserStatus model.
    class StateGenerator < Rails::Generators::NamedBase
      include ActiveRecord::Generators::Migration

      DEFAULT_STATE_COLUMN = "status"

      source_root Pathname(__dir__).join("templates")

      argument :base_name, type: :string, banner: "base_name"

      class_option :state_column, type: :string, default: DEFAULT_STATE_COLUMN,
        desc: "The state table's column holding the state"
      class_option :primary_key_type, type: :string,
        desc: "The type for primary key"
      class_option :database, type: :string, aliases: %i[--db],
        desc: "The database for the migration"

      def create_migration_file
        migration_template "migration.rb.tt",
          Pathname(db_migrate_path).join("create_#{state_table_name}.rb")
      end

      def create_model_file
        template "model.rb.tt", Pathname("app/models").join("#{state_file_name}.rb")
      end

      # Like Rails' model generator, creates the abstract class the model
      # inherits from with --database, unless it already exists
      def create_database_abstract_class
        return unless options[:database]

        path = Pathname("app/models").join("#{options[:database].underscore}_record.rb")
        return if Pathname(destination_root).join(path).exist?

        template "abstract_class.rb.tt", path
      end

      def show_has_current
        say ""
        say "Add to app/models/#{file_path}.rb, with your own states:"
        say ""
        say has_current_lines.map { |line| "  #{line}" }.join("\n")
      end

      private

      def has_current_lines
        [
          "include AppendTransitions::HasCurrent.new(",
          "  :#{base_name},",
          "  class_name: #{state_class_name.inspect},",
          *state_column_lines,
          "  initial_state: :pending,",
          "  transitions: {pending: [:approved, :denied]}",
          ")"
        ]
      end

      def state_column_lines
        if state_column == DEFAULT_STATE_COLUMN
          []
        else
          ["  state_column: :#{state_column},"]
        end
      end

      def state_column
        options[:state_column]
      end

      def state_class_name
        "#{class_name}#{base_name.camelize}"
      end

      # Admin::UserStatus => admin_user_statuses, like Rails names the
      # table for a namespaced model
      def state_table_name
        state_class_name.tableize.tr("/", "_")
      end

      def state_file_name
        state_class_name.underscore
      end

      # ActiveRecord's helpers of the same name only read the option.
      # Rails' own generators also get the app's default from
      # config.generators, under a namespace this generator doesn't share.
      def primary_key_type
        key_type && ", id: :#{key_type}"
      end

      def foreign_key_type
        key_type && ", type: :#{key_type}"
      end

      def key_type
        options[:primary_key_type] ||
          Rails::Generators.options.dig(:active_record, :primary_key_type)
      end

      # A namespaced parent's table (admin_users) can't be inferred from
      # the reference name (user)
      def foreign_key_option
        if class_path.empty?
          "true"
        else
          "{to_table: :#{table_name}}"
        end
      end

      def parent_class_name
        if options[:database]
          database_class_name
        else
          "ApplicationRecord"
        end
      end

      def database_class_name
        "#{options[:database].camelize}Record"
      end

      def index_lines
        RecommendedIndex.new(
          table_name: state_table_name,
          foreign_key: "#{singular_name}_id",
          order: HasCurrent::DEFAULT_ORDER,
          state_column:
        ).lines
      end
    end
  end
end
