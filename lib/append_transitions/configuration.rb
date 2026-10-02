# frozen_string_literal: true

module AppendTransitions
  class Configuration
    VALID_ON_MISSING_INDEX = %i[raise warn].freeze

    attr_reader :on_missing_index

    def initialize
      @on_missing_index = :warn
    end

    def on_missing_index=(value)
      unless VALID_ON_MISSING_INDEX.include?(value)
        options = VALID_ON_MISSING_INDEX.join(", ")
        message = "on_missing_index must be one of: #{options}"

        raise ArgumentError, message
      end

      @on_missing_index = value
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end
  end
end
