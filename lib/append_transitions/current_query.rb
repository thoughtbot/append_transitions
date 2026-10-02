# frozen_string_literal: true

module AppendTransitions
  class CurrentQuery
    include ForeignKey

    def initialize(class_name:, order:, foreign_key:)
      @class_name = class_name
      @foreign_key = foreign_key
      @order = order
    end

    def call(record)
      @class_name.constantize
        .where(fk_for(record.class) => record.id)
        .order(@order)
        .first
    end
  end
end
