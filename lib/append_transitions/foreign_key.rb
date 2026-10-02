# frozen_string_literal: true

module AppendTransitions
  # Resolves the configured @foreign_key, or infers it from the owner
  # class the same way Rails does for has_many (User => user_id). Uses
  # base_class so STI subclasses (Admin < User) still resolve to user_id.
  module ForeignKey
    private

    def fk_for(owner)
      @foreign_key || owner.base_class.model_name.to_s.foreign_key
    end
  end
end
