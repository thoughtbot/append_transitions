# frozen_string_literal: true

module AppendTransitions
  # The index current_* and with_current_* read through: the foreign key,
  # then the order columns. IndexValidator checks for it, and both the
  # missing index message and the generator write it out.
  class RecommendedIndex
    # PostgreSQL's limit on identifier length
    MAX_NAME_LENGTH = 63

    def initialize(table_name:, foreign_key:, order:, state_column:)
      @table_name = table_name
      @foreign_key = foreign_key
      @order = order
      @state_column = state_column
    end

    # The add_index call for this index, as an array with one argument
    # per string and a trailing comma on all but the last:
    #
    #   ["add_index :user_statuses, [:user_id, :created_at, :id],",
    #    "order: {created_at: :desc, id: :desc},",
    #    "include: :status"]
    #
    # Callers join it to fit their output: with spaces for the one-line
    # missing index message, with indented newlines for the generated
    # migration.
    #
    # Before ActiveRecord 7.1, include isn't supported, so it's left out,
    # and long index names aren't shortened, so a short name is added
    # when the default would be too long.
    def lines
      arguments = [columns_argument, order_argument]
      include_supported? && arguments << include_argument
      name_required? && arguments << name_argument

      arguments[...-1].map { |argument| "#{argument}," } << arguments.last
    end

    def columns
      [@foreign_key, *@order.keys].map(&:to_sym)
    end

    private

    def columns_argument
      "add_index #{@table_name.to_sym.inspect}, #{columns.inspect}"
    end

    def order_argument
      pairs = @order.map { |column, direction| "#{column}: #{direction.to_sym.inspect}" }

      "order: {#{pairs.join(", ")}}"
    end

    def include_supported?
      active_record_7_1_or_later?
    end

    def include_argument
      "include: #{@state_column.to_sym.inspect}"
    end

    def name_required?
      !active_record_7_1_or_later? && default_name.length > MAX_NAME_LENGTH
    end

    def name_argument
      "name: #{"index_#{@table_name}_current".inspect}"
    end

    # The name ActiveRecord 7.0 gives the index
    def default_name
      "index_#{@table_name}_on_#{columns.join("_and_")}"
    end

    def active_record_7_1_or_later?
      ActiveRecord.version >= Gem::Version.new("7.1")
    end
  end
end
