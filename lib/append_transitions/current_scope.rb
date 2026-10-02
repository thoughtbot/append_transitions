# frozen_string_literal: true

module AppendTransitions
  class CurrentScope
    include ForeignKey

    def initialize(class_name:, attr_name:, foreign_key:, order:)
      @class_name = class_name
      @attr_name = attr_name
      @foreign_key = foreign_key
      @order = order
      @hydrator = Hydrator.new(class_name:, attr_name:)
    end

    def call(base)
      subquery = subquery_for(base)

      base
        .select(base.arel_table[Arel.star], *aliased_columns)
        .joins("LEFT JOIN LATERAL (#{subquery.to_sql}) #{quoted_alias} ON true")
        .extending(@hydrator, CountAll)
    end

    private

    def subquery_for(base)
      klass
        .where(join_condition(base))
        .order(@order)
        .limit(1)
    end

    # Arel quotes the names and uses the base's real primary key
    def join_condition(base)
      foreign_key = klass.arel_table[fk_for(base)]
      primary_key = base.arel_table[base.primary_key]

      foreign_key.eq(primary_key)
    end

    # Quoted, so mixed-case column names keep their case. The hydrator
    # reads them back as current_status_<column>.
    def aliased_columns
      klass.column_names.map do |column|
        "#{quoted_alias}.#{quote(column)} AS #{quote("#{@attr_name}_#{column}")}"
      end
    end

    def quoted_alias
      quote(@attr_name)
    end

    def quote(name)
      klass.connection.quote_column_name(name)
    end

    def klass
      @klass ||= @class_name.constantize
    end
  end
end
