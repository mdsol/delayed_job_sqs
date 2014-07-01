module Delayed
  module Backend
    module Sqs
      module Actions
        def field(name, options = {})
          default = options[:default] || nil
          define_method name do
            @attributes ||= {}
            @attributes[name.to_sym] || default
          end

          define_method "#{name}=" do |value|
            @attributes ||= {}
            @attributes[name.to_sym] = value
          end
        end

        def before_fork
        end

        def after_fork
        end

        def db_time_now
          Time.now.utc
        end

        # Find an available job message on the queue for the given worker to start working on.
        # Only jobs which are not failed and which should not be run in the future are given to the worker.
        def find_available(worker_name, limit = 5, max_run_time = Worker.max_run_time)
          Delayed::Worker.queues.each_with_index do |queue, index|
            message = sqs.queues.named(queue_name(index)).receive_message
            
            if message
              job = Delayed::Backend::Sqs::Job.new(message)
              # Note:  if the message isn't suitable, we won't delete it.  We'll just let its visibility timeout
              # expire so that it can be looked at again in the future.  After all, it may be set to run_at in the future.
              # TODO:  remove failed jobs and put them in s3.
              # TODO:  should maybe just make unsuitable message visible right away again here.
              return [job] if is_job_suitable?(job)
            end
          end
          []
        end

        # Returns true if the job encoded in a message is suitable to be run by a worker; otherwise, return false.
        def is_job_suitable?(job)
          job.failed_at.nil? && (job.run_at.nil? || job.run_at <= db_time_now)
        rescue TypeError, JSON::ParserError => e
          puts "Cannot parse job description #{job_message} to determine if it is suitable because #{e.message} (#{e.class})."
          false # we should never run a job which can't be parsed!
        end
        
        def delete_all
          deleted = 0

          Delayed::Worker.queues.each_with_index do |queue, index|
            loop do
              msgs = sqs.queues.named(queue_name(index)).receive_message({ :limit => 10})
              break if msgs.blank?
              msgs.each do |msg|
                msg.delete
                deleted += 1
              end
            end
          end

          puts "Messages removed: #{deleted}"
        end

        # No need to check locks
        def clear_locks!(*args)
          true
        end

        private

        def sqs
          ::Delayed::Worker.sqs
        end

        def queue_name(index)
          Delayed::Worker.queues[index]
        end
      end
    end
  end
end
