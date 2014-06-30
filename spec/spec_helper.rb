SPEC_DIR = File.expand_path("..", __FILE__)
LIB_DIR = File.expand_path("../lib", SPEC_DIR)

$LOAD_PATH.unshift(LIB_DIR)
$LOAD_PATH.uniq!

require 'bundler'
require 'simplecov'
require 'debugger'

SimpleCov.start do
  add_group 'lib', 'lib'
  add_filter 'spec'
end

require 'rspec'
require 'delayed_job'

Bundler.setup

require 'fake_sqs/test_integration'
require 'aws-sdk'

Dir["#{SPEC_DIR}/support/*.rb"].each { |f| require f }

QUEUE_NAME = 'default' # A queue name to be used by default by both delayed_jobs and delayed_jobs_sqs.

# Define AWS config. to be used in tests.  This is for the benefit of telling delayed_job_sqs where the sqs endpoint is
# and what credentials to use to talk to it.  Here, we use localhost b/c we are using fake_sqs as our SQS endpoint.
AWS.config(
  use_ssl:            false,
  sqs_endpoint:       'localhost',
  sqs_port:           4568,
  access_key_id:      'fake',
  secret_access_key:  'fake',
  sqs_queue_name:     QUEUE_NAME,
)

require File.join(LIB_DIR, 'delayed_job_sqs')

# Tell DJ where to log.  These logs are useful for debugging purposes.
Delayed::Worker.logger = Logger.new('/tmp/dj.log')

# TODO:  Shouldn't DJ_SQS just set the queue name(s)?
Delayed::Worker.queues = [QUEUE_NAME]

RSpec.configure do |config|  
  config.mock_with :rspec
  config.treat_symbols_as_metadata_keys_with_true_values = true
  
  # Before running the test suite, initialize and start fake_sqs.
  config.before(:suite) do 
    $fake_sqs = FakeSQS::TestIntegration.new(database: ':memory:')
    $fake_sqs.start
    $sqs = AWS::SQS.new
  end
  
  # Each example tagged with :sqs, we reset fake_sqs and recreate the SQS queue in which we store jobs.
  config.before(:each, :sqs) do
    $fake_sqs.reset
    $sqs.queues.create(QUEUE_NAME)
  end
  
  # After running the test suite, stop fake_sqs.
  config.after(:suite) { $fake_sqs.stop }
end
