# frozen_string_literal: true

module AppendTransitions
  # Defines, for base name :status:
  #
  #   user.current_status          # cached latest UserStatus, or nil
  #   user.transition_status(:new) # appends a row under a row lock,
  #                                # clears @current_status
  #   user.reload                  # also clears @current_status
  #   User.with_current_status     # LATERAL join, hydrates @current_status
  class HasCurrent < Module
    DEFAULT_ORDER = {created_at: :desc, id: :desc}.freeze

    def initialize(
      base_name, class_name:, initial_state:, transitions: {}, foreign_key: nil,
      state_column: :status, order: DEFAULT_ORDER
    )
      super()

      validate_order!(order)

      @base_name = base_name
      base_args = {class_name:, foreign_key:}
      attr_name = :"current_#{base_name}"
      ivar = :"@#{attr_name}"

      current_query = CurrentQuery.new(**base_args, order:)
      transition_map = TransitionMap.new(initial_state:, transitions:)
      transitioner = Transitioner.new(**base_args, state_column:, transition_map:, current_query:)
      current_scope = CurrentScope.new(**base_args, attr_name:, order:)
      index_validator = IndexValidator.new(**base_args, state_column:, order:)

      # Drops the cached value, so the next read queries again
      clear_current = proc do
        instance_variable_defined?(ivar) && remove_instance_variable(ivar)
      end

      # def current_status
      #
      # Caches the result, including nil, like Rails associations do.
      define_method(attr_name) do
        if instance_variable_defined?(ivar)
          instance_variable_get(ivar)
        else
          index_validator.validate!(self.class)
          instance_variable_set(ivar, current_query.call(self))
        end
      end

      # def transition_status(new_state, &block)
      define_method(:"transition_#{base_name}") do |new_state, &block|
        transitioner.call(self, new_state, &block).tap do
          instance_exec(&clear_current)
        end
      end

      # def reload(*args)
      define_method(:reload) do |*args|
        instance_exec(&clear_current)
        super(*args)
      end

      @class_methods = Module.new do
        # def self.with_current_status
        define_method(:"with_#{attr_name}") do
          index_validator.validate!(self)
          current_scope.call(self)
        end
      end
    end

    def included(base)
      super

      base.extend(@class_methods)
    end

    def inspect
      "HasCurrent(:#{@base_name})"
    end

    private

    # The recommended index and the missing index check are built from
    # the order's columns, so it can't be raw SQL.
    def validate_order!(order)
      unless order.is_a?(Hash)
        raise ArgumentError, "order must be a Hash of columns to directions, got #{order.inspect}"
      end
    end
  end
end
