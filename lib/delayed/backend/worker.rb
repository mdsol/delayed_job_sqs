require_relative 'sqs_config'

module Delayed
  class Worker

    class << self
      attr_accessor :config, :sqs, :delay, :timeout, :expires_in, :aws_config

      def configure
        yield(config) if block_given?

        self.default_queue_name = if !config.default_queue_name.nil? && config.default_queue_name.length != 0
                        config.default_queue_name
                      else
                        'default'
                      end
        self.delay = config.delay_seconds || 0
        self.timeout = config.visibility_timeout || 5.minutes
        self.expires_in = config.message_retention_period || 96.hours
      end

      def config
        @config ||= SqsConfig.new
      end
    end
  end

  module Backend
    module Sqs
      if Object.const_defined?(:Rails) and Rails.const_defined?(:Railtie)
        class Railtie < Rails::Railtie

          # configure our gem after Rails completely boots so that we have
          # access to any config/initializers that were run
          config.after_initialize do
            Aws::Rails.setup

            Delayed::Worker.sqs = Aws::SQS::Resource.new(region: Aws.config[:region])
            Delayed::Worker.configure {}
          end
        end
      elsif defined?(Aws.config) &&
        Aws.config[:credentials].access_key_id &&
        Aws.config[:credentials].secret_access_key

        # Use config in Aws.config if it is defined well enough for our sqs-y purposes.
        Delayed::Worker.sqs = Aws::SQS::Resource.new(region: Aws.config[:region])
        Delayed::Worker.configure {}
      else
        path = Pathname.new(Delayed::Worker.config.aws_config)

        if File.exists?(path)
          cfg = YAML::load(File.read(path))

          unless cfg.keys[0]
            raise "Aws Yaml configuration file is missing a section"
          end

          Aws.config(cfg.keys[0])
        end

        Delayed::Worker.sqs = Aws::SQS::Client.new(region: Aws.config[:region])
        Delayed::Worker.configure {}
      end
    end
  end
end


