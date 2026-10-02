# frozen_string_literal: true

module AppendTransitions
  class TransitionMap
    def initialize(initial_state:, transitions:)
      unless initial_state.is_a?(Symbol) || initial_state.is_a?(String)
        raise ArgumentError, "initial_state must be a single state, got #{initial_state.inspect}"
      end

      if transitions.key?(nil)
        raise ArgumentError, "transitions cannot have a nil key, use initial_state instead"
      end

      # Normalize to symbols so string states (e.g. from YAML) match.
      @transitions = {nil => initial_state, **transitions}
        .to_h { |from, to| [from&.to_sym, Array(to).map(&:to_sym)] }
    end

    def valid?(from:, to:)
      possible_states(from).include?(to)
    end

    private

    def possible_states(state)
      @transitions.fetch(state, [])
    end
  end
end
