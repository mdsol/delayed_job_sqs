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

        MAX_MESSAGES_IN_BATCH = 10

        def self.buffering?
          @buffering
        end

        def buffering?
          self.class.buffering?
        end

        def self.start_buffering!
          @buffering = true
        end

        def self.stop_buffering!
          @buffering = false
        end

        def self.clear_buffer!
          @buffer = nil
        end

        def self.buffer
          @buffer ||= {}
        end

        def buffer
          self.class.buffer
        end

        def initialize(data = {})
          puts "[init] Delayed::Backend::Sqs"
          @msg = nil

          if data.is_a?(AWS::SQS::ReceivedMessage)
            @msg = data
            data = ::DelayedJobSqs::Document.sqs_safe_json_load(data.body)
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
          puts "Failed to serialize #{object} because #{e.message} (#{e.class})."
          # If we have trouble serializing the object, simply assume it is already serialized and store it as is
          # in hopes that it can be deserialized when the time comes.  This is what the dj lint calls for.
          self.handler = object
        end

        def save
          puts "[SAVE] #{@attributes.inspect}"

          if @attributes[:handler].blank?
            raise "Handler missing!"
          end
          payload = ::DelayedJobSqs::Document.sqs_safe_json_dump(@attributes)

          @msg.delete if @msg

          if buffering?
            add_to_buffer(message_body: payload, delay_seconds: @delay)
          else
            sqs.queues.named(queue_name).send_message(payload, delay_seconds: @delay )
          end
          true
        end

        def save!
          save
        end

        def add_to_buffer(message)
          buffer[@queue_name] = [[]] unless buffer[@queue_name]
          current_buffer = buffer[@queue_name]

          if buffer_over_limit?(current_buffer, message[:message_body])
            current_buffer << [message]
          else
            current_buffer.last << message
          end
        end

        def self.persist_buffer!
          buffer.each do |queue_name, message_batches|
            message_batches.each do |message_batch|
              sqs.queues.named(queue_name).batch_send(message_batch) if message_batch.size > 0
            end
          end
        end

        def destroy
          if @msg
            message_id = @msg.id
            @msg.delete # TODO:  need more fault tolerance around this!
            puts "Job destroyed! #{message_id} \nWith attributes: #{@attributes.inspect}"
          else
            puts "Could not destroy job b/c no SQS message provided: #{@attributes.inspect}"
          end
        end

        # Mark the job as failed (i.e. set failed_at to the current time).
        # TODO:  Put failed jobs in s3 or onto a failed job queue (if they are set to be retained).
        # TODO:  Need more fault tolerance in this method.
        def fail!
          puts "Job with attributes #{@attributes.inspect} failed!"
          if Delayed::Worker.destroy_failed_jobs
            destroy
          else
            update_attributes(failed_at: Time.now.utc)
          end
        end

        def update_attributes(attributes)
          attributes.symbolize_keys!
          @attributes.merge! attributes
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

        def buffer_over_limit?(target_buffer, added_message)
          target_buffer_size = target_buffer.last.reduce(0) { |m, msg| m + msg[:message_body].bytesize }
          total_buffer_size = target_buffer_size + added_message.bytesize

          total_buffer_size >= ::DelayedJobSqs::Document::MAX_SQS_MESSAGE_SIZE_IN_BYTES ||
            target_buffer.last.size >= MAX_MESSAGES_IN_BATCH
        end
      end
    end
  end
end
