# frozen_string_literal: true

require_relative "append_transitions/version"
require_relative "append_transitions/configuration"
require_relative "append_transitions/foreign_key"
require_relative "append_transitions/transition_map"
require_relative "append_transitions/current_query"
require_relative "append_transitions/transitioner"
require_relative "append_transitions/hydrator"
require_relative "append_transitions/count_all"
require_relative "append_transitions/current_scope"
require_relative "append_transitions/recommended_index"
require_relative "append_transitions/index_validator"
require_relative "append_transitions/has_current"

module AppendTransitions
  class Error < StandardError; end
  class InvalidTransition < Error; end
  class MissingIndexError < Error; end
end
