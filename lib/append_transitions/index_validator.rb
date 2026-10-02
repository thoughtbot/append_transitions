# frozen_string_literal: true

module AppendTransitions
  # Checks that the child table has an index starting with the
  # RecommendedIndex columns (foreign key, then the order columns).
  # Without one, each lookup scans or sorts the parent's rows. Order
  # directions and INCLUDE aren't checked: PostgreSQL can scan an index
  # backward, and the index works without INCLUDE, only slower.
  class IndexValidator
    include ForeignKey

    def initialize(class_name:, foreign_key:, state_column:, order:)
      @class_name = class_name
      @foreign_key = foreign_key
      @state_column = state_column
      @order = order
      @validated = false
    end

    def validate!(owner)
      # Concurrent calls may both pass this guard, which is harmless
      # in practice. It's a brief window and the check is a read-only
      # catalog lookup.
      return if @validated

      klass = @class_name.constantize
      table_name = klass.table_name
      index = recommended_index(table_name, fk_for(owner))

      unless index_exists?(klass.connection, table_name, index)
        report_missing_index(table_name, index)
      end

      @validated = true
    end

    private

    def recommended_index(table_name, fk)
      RecommendedIndex.new(
        table_name:, foreign_key: fk, order: @order, state_column: @state_column
      )
    end

    def index_exists?(connection, table_name, index)
      columns = index.columns.map(&:to_s)

      connection.indexes(table_name).any? do |existing|
        covers?(existing, columns)
      end
    end

    # Expression indexes report their columns as a String, and partial
    # indexes leave rows out, so neither counts.
    def covers?(existing, columns)
      existing.columns.is_a?(Array) &&
        existing.where.nil? &&
        existing.columns.first(columns.size) == columns
    end

    def report_missing_index(table_name, index)
      message = message_for(table_name, index)

      case AppendTransitions.configuration.on_missing_index
      when :raise
        raise MissingIndexError, message
      when :warn
        warn message
      end
    end

    def message_for(table_name, index)
      <<~MSG.squish
        AppendTransitions: no index on "#{table_name}" starting with
        (#{index.columns.join(", ")}).
        Lookups of the current state will slow down as history grows.
        Add to a migration: #{index.lines.join(" ")}
      MSG
    end
  end
end
