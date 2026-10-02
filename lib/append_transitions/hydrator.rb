# frozen_string_literal: true

module AppendTransitions
  # Hooks into ActiveRecord::Relation#load via .extending to turn flat
  # lateral join rows into hydrated AR objects on each parent record.
  #
  #   #<User id: 1, current_status_id: 42, current_status_status: "approved">
  #   => user.@current_status = #<UserStatus id: 42, status: "approved">
  #
  # Uses @records (AR::Relation internal, stable since Rails 3, same
  # approach as the Goldiloader and Bullet gems).
  class Hydrator < Module
    def initialize(class_name:, attr_name:)
      super()

      klass_name = class_name
      name = attr_name
      ivar = :"@#{attr_name}"

      # Forwards the block, which the preloader uses to set inverses
      define_method(:load) do |&block|
        # Hydrates only when this call runs the query. Records of an
        # already loaded relation may have moved on, e.g. a transition
        # cleared their state.
        return super(&block) if loaded?

        super(&block).tap do
          klass = klass_name.constantize

          @records.each do |record|
            # Without the selected columns (e.g. after reselect), the state
            # is left to be queried on first read, one query per record
            next unless record.has_attribute?("#{name}_id")

            attrs = klass.column_names.each_with_object({}) do |col, h|
              h[col] = record.read_attribute("#{name}_#{col}")
            end

            # Sets nil explicitly, so a row without a status counts as loaded
            obj = attrs["id"].presence && klass.instantiate(attrs.stringify_keys)
            record.instance_variable_set(ivar, obj)
          end
        end
      end
    end
  end
end
