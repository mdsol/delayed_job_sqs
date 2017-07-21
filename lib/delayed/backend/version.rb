module Delayed
  module Backend
    module Sqs
      @@version = nil

      def self.version
        @@version ||= "0.2.1"
      end
    end
  end
end
