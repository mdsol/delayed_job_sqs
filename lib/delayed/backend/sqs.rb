
module Delayed
  module Backend
    module Sqs
      class Job
        include ::DelayedJobSqs::Document
        include Delayed::Backend::Base
        extend  Delayed::Backend::Sqs::Actions

        field :priority,    :type => Integer, :default => 0
        field :attempts,    :type => Integer, :default => 0
        field :handler,     :type => String
        field :run_at,      :type => Time # TODO:  implement run_at
        field :locked_at,   :type => Time
        field :locked_by,   :type => String
        field :failed_at,   :type => Time
        field :last_error,  :type => String
        field :queue,       :type => String

        def initialize(data = {})
          puts "[init] Delayed::Backend::Sqs"
          @msg = nil

          if data.is_a?(AWS::SQS::ReceivedMessage)
            @msg = data
            data = JSON.load(data.body)
          end

          data.symbolize_keys!
          payload_obj = data.delete(:payload_object) || data.delete(:handler)
          
          # Ensure that run_at is present and is a Time object.
          data[:run_at] = if data[:run_at].nil?
            Time.now.utc
          elsif data[:run_at].is_a?(String)
            Time.parse(data[:run_at])
          else
            data[:run_at]
          end
          
          @queue_name = data[:queue]      || Delayed::Worker.default_queue_name
          @delay      = data[:delay]      || Delayed::Worker.delay
          @timeout    = data[:timeout]    || Delayed::Worker.timeout
          @expires_in = data[:expires_in] || Delayed::Worker.expires_in
          @attributes = data
          self.payload_object = payload_obj
        end

        def self.create(attrs = {})
          new(attrs).tap do |o|
            o.save
          end
        end

        def self.create!(attrs = {})
          new(attrs).tap do |o|
            o.save!
          end
        end
        
        def payload_object
          @payload_object ||= YAML.load(self.handler)
        rescue TypeError, LoadError, NameError, ArgumentError => e
          raise Delayed::DeserializationError,
            "Job failed to load: #{e.message}. Handler: #{handler.inspect}"
        end

        def payload_object=(object)
          if object.is_a? String
            @payload_object = YAML.load(object)
            self.handler = object
          else
            @payload_object = object
            self.handler = object.to_yaml
          end
        rescue TypeError, LoadError, NameError, ArgumentError => e
          # If we have trouble serializing the object, simply assume it is already serialized and store it as is
          # in hopes that it can be deserialized when the time comes.  This is what the dj lint calls for.
          self.handler = object
        end

        def save
          puts "[SAVE] #{@attributes.inspect}"

          if @attributes[:handler].blank?
            raise "Handler missing!"
          end
          payload = JSON.dump(@attributes)

          @msg.delete if @msg
          sqs.queues.named(queue_name).send_message(payload, :delay_seconds  => @delay)
          true
        end

        def save!
          save
        end

        def destroy
          if @msg
            puts "job destroyed! #{@msg.id} \nWith attributes: #{@attributes.inspect}"
            @msg.delete
          end
        end

        # TODO:  Put failed jobs in s3 (if they are set to be retained).
        def fail!
          if @msg
            puts "job failed without being destroyed! #{@msg.id} \nWith attributes: #{@attributes.inspect}"
          end
          destroy
        end

        def update_attributes(attributes)
          attributes.symbolize_keys!
          @attributes.merge attributes
          save
        end

        # No need to check locks
        def lock_exclusively!(*args)
          true
        end

        # No need to check locks
        def unlock(*args)
          true
        end

        # This method is supposed to reload the payload object.
        # NOTE:  I can't find evidence that this is actually called in anything but tests by delayed job.
        # We are copying the implementation given in delayed_job/spec/delayed/backend/test.rb 
        def reload(*args)
          reset
          self
        end

        # Count the total number of jobs in all queues.
        def self.count
          num_jobs = 0
          Delayed::Worker.queues.each_with_index do |queue, index|
            queue = sqs.queues.named(queue_name(index))
            num_jobs += queue.approximate_number_of_messages + queue.approximate_number_of_messages_delayed + queue.approximate_number_of_messages_not_visible
          end
          num_jobs
        end
                
        # Must give each job an id.
        def id
          rand(10e6)
        end
                
        private

        def queue_name
          @queue_name
        end

        def sqs
          ::Delayed::Worker.sqs
        end
      end
    end
  end
end
