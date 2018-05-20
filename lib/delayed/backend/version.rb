module Delayed
  module Backend
    module Sqs
      @@version = nil

      def self.version
        @@version ||= "1.0.0"
      end
    end
  end
end
