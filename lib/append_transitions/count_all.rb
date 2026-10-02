# frozen_string_literal: true

module AppendTransitions
  # Added to with_current_* relations via .extending. A bare count would
  # wrap the aliased select in COUNT(...), which is invalid SQL, so it
  # counts all rows instead.
  module CountAll
    def count(column_name = nil, &block)
      return super if block

      super(column_name || :all)
    end
  end
end
