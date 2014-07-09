require 'spec_helper'
require 'delayed/backend/shared_spec'
require 'active_record'
require 'fake_sqs'

# This story class is a simple class required by the shared specs.  It is in fact copied from DJ repo.
# The shared specs expect the Story class to have a lot of ActiveRecord-like qualities so I'm just 
# making it an ActiveRecord-based class.
# Used to test interactions between DJ and an ORM
ActiveRecord::Base.establish_connection :adapter => 'sqlite3', :database => ':memory:'
ActiveRecord::Base.logger = Delayed::Worker.logger
ActiveRecord::Migration.verbose = false
  
ActiveRecord::Schema.define do
  create_table :stories, :primary_key => :story_id, :force => true do |table|
    table.string :text
    table.boolean :scoped, :default => true
  end
end

class Story < ActiveRecord::Base
  self.primary_key = 'story_id'
  def tell; text; end
  def whatever(n, _); tell*n; end
  default_scope { where(:scoped => true) }

  handle_asynchronously :whatever
end

describe Delayed::Backend::Sqs::Job, :sqs do
  it_behaves_like 'a delayed_job backend'
  
  let(:simple_job) { DelayedJobSqs::SimpleJob.new }
  
  let(:sqs_message) { AWS::SQS::ReceivedMessage.new(AWS::SQS::Queue.new("http://0.0.0.0:#{AWS.config.sqs_port}/#{DEFAULT_QUEUE_NAME}"),
   1, "", opts = {body: {job: "New job"}.to_json}) }
  
  let(:sqs_job) { Delayed::Backend::Sqs::Job.new(sqs_message) }
  
  [1, 2].each do |num_jobs|
    it "delays #{num_jobs} simple job(s) successfully" do
      before_runs_count = DelayedJobSqs::SimpleJob.runs
    
      num_jobs.times{ simple_job.delay.perform }
      Delayed::Worker.new.work_off
    
      DelayedJobSqs::SimpleJob.runs.should == (before_runs_count + num_jobs)
    end
  end
  
  after do
    $fake_sqs.start
    $fake_sqs.clear_failure
  end
  
  describe 'enqueue' do

    it 'raises if AWS SQS returns non ok status' do
      $fake_sqs.api_fail('send_message')
      expect {described_class.enqueue(payload_object: SimpleJob.new)}.to raise_error(FakeSQS::InvalidAction)
    end
    
    it 'raises if AWS SQS fails to respond' do
      $fake_sqs.stop
      expect {described_class.enqueue(payload_object: SimpleJob.new)}.to raise_error(Errno::ECONNREFUSED)
    end

  end
  
  describe 'fail' do
    
    context 'with sqs message' do
      
      after do
        sqs_job.fail!
      end
      
      it 'destroys the job' do
        sqs_message.should_receive(:delete)
      end
    
      it 'logs the failure' do
        sqs_job.should_receive(:puts).with(/Job with attributes/)
        sqs_job.should_receive(:puts).with(/Job destroyed!/)
      end
    end
    
    it 'logs the failure to destroy the job without sqs message' do
      sqs_job_no_msg = Delayed::Backend::Sqs::Job.new
      sqs_job_no_msg.should_receive(:puts).with(/Job with attributes/)
      sqs_job_no_msg.should_receive(:puts).with(/Could not destroy job/)
      sqs_job_no_msg.fail!
    end

  end
  
  describe 'retry' do
    
    it 'does not delete the job if failed to resend it' do
      $fake_sqs.api_fail('send_message')
      sqs_message.should_not_receive(:delete)
      expect { sqs_job.save }.to raise_error(AWS::SQS::Errors::InvalidAction)
    end
  end
  
end
