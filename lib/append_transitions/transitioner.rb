# frozen_string_literal: true

module AppendTransitions
  # Inserts a new state record under a SELECT FOR UPDATE lock on the
  # parent row. Validates the transition against the TransitionMap,
  # creates the row, and yields the inserted record to an optional block.
  # The entire operation runs in one transaction, so concurrent
  # transitions on the same parent are serialized.
  class Transitioner
    include ForeignKey

    def initialize(class_name:, foreign_key:, state_column:, transition_map:, current_query:)
      @class_name = class_name
      @foreign_key = foreign_key
      @state_column = state_column
      @transition_map = transition_map
      @current_query = current_query
    end

    def call(record, new_state, &block)
      ensure_saved(record)

      record.transaction do
        lock(record)
        current = @current_query.call(record)
        new_state = validate_transition(current, new_state)
        state_record = create_transition(record, new_state, current)
        block&.call(state_record)
        state_record
      end
    end

    private

    # A new record has no row to lock, and no id to reference
    def ensure_saved(record)
      return unless record.new_record?

      message = "Cannot transition a new record, save it first"
      raise ActiveRecord::RecordNotSaved.new(message, record)
    end

    # Not with_lock: it reloads the record and refuses records with
    # unsaved changes, and a transition shouldn't touch the parent's
    # attributes. unscoped keeps a default scope on the parent (e.g. a
    # soft-delete filter) from hiding the row being locked.
    def lock(record)
      record.class.unscoped.lock.find(record.id)
    end

    def validate_transition(current, new_state)
      from = current&.public_send(@state_column)&.to_sym

      new_state&.to_sym.tap do |to|
        unless @transition_map.valid?(from:, to:)
          message = "Cannot transition from #{from || "nil"} to #{to || "nil"}"
          raise InvalidTransition, message
        end
      end
    end

    def create_transition(record, new_state, current)
      klass.create!(
        fk_for(record.class) => record.id,
        @state_column => new_state,
        **timestamps_after(current)
      )
    end

    # created_at comes from this process's clock, which may be behind the
    # one that wrote the current row. Rows are ordered by it, so keep it
    # after the current row's.
    def timestamps_after(current)
      if current&.has_attribute?(:created_at)
        {created_at: [Time.current, current.created_at + 1.0e-6].max}
      else
        {}
      end
    end

    def klass
      @klass ||= @class_name.constantize
    end
  end
end
