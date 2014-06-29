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

QUEUE_NAME = 'default'
AWS.config(
  use_ssl:            false,
  sqs_endpoint:       'localhost',
  sqs_port:           4568,
  access_key_id:      'fake',
  secret_access_key:  'fake',
  sqs_queue_name:     QUEUE_NAME,
)

require File.join(LIB_DIR, 'delayed_job_sqs')


RSpec.configure do |config|  
  config.mock_with :rspec
  config.treat_symbols_as_metadata_keys_with_true_values = true
  
  config.before(:suite) do 
    $fake_sqs = FakeSQS::TestIntegration.new(database: ':memory:')
    $fake_sqs.start
    $sqs = AWS::SQS.new
  end
  
  config.before(:each, :sqs) do
    $fake_sqs.reset
    $sqs.queues.create(QUEUE_NAME)
  end
  
  config.before(:each) do
    Delayed::Worker.logger = Logger.new('/tmp/dj.log')
    # TODO:  Shouldn't DJ_SQS just set the queue name(s)?
    Delayed::Worker.queues = [QUEUE_NAME]
  end
  
  config.after(:suite) { $fake_sqs.stop }
end
