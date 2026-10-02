module AppendTransitions
  module TestHelpers
    def build_user_status_class(namespace)
      Class.new(ActiveRecord::Base) do
        self.table_name = "user_statuses"

        belongs_to :user, class_name: "#{namespace}::User"
      end
    end

    def build_user_class(
      user_status_class,
      base_name: :status,
      initial_state: :pending,
      transitions: {
        pending: [:approved, :denied],
        denied: :pending
      },
      **options
    )
      Class.new(ActiveRecord::Base) do
        self.table_name = "users"

        include AppendTransitions::HasCurrent.new(
          base_name,
          class_name: user_status_class.name,
          initial_state:,
          transitions:,
          **options
        )
      end
    end

    def count_queries(&block)
      count = 0
      counter = ->(*, payload) { payload[:name] == "SCHEMA" || count += 1 }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      count
    end
  end
end
