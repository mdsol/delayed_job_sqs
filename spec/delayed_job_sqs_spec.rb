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
  # TODO: Uncomment this line when the adapter actually passes these specs.
  # it_behaves_like 'a delayed_job backend'
  
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
      expect {described_class.enqueue(payload_object: SimpleJob.new)}.to raise_error(AWS::SQS::Errors::InvalidAction)
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
    it 'does not destroy the job if failed to resend it' do
      $fake_sqs.api_fail('send_message')
      sqs_message.should_not_receive(:destroy)
      expect { sqs_job.save }.to raise_error(AWS::SQS::Errors::InvalidAction)
    end
  end

  describe '.batch_delay_jobs' do
    it 'adds jobs into the buffer' do
      Delayed::Job.batch_delay_jobs do
        described_class.enqueue(payload_object: SimpleJob.new)
        expect(Delayed::Job.buffer[DEFAULT_QUEUE_NAME].first.size).to eq(1)
        described_class.enqueue(payload_object: SimpleJob.new)
        expect(Delayed::Job.buffer[DEFAULT_QUEUE_NAME].first.size).to eq(2)
      end
    end

    context 'when batch_delay_jobs blocks are nested' do
      it 'adds all jobs to the same buffer' do
        Delayed::Job.batch_delay_jobs do
          described_class.enqueue(payload_object: SimpleJob.new)

          Delayed::Job.batch_delay_jobs do
            described_class.enqueue(payload_object: SimpleJob.new)
            expect(Delayed::Job.buffer[DEFAULT_QUEUE_NAME].first.size).to eq(2)
          end
        end
      end

      it 'adds jobs after nested blocks to a newly emptied queue' do
        Delayed::Job.batch_delay_jobs do
          described_class.enqueue(payload_object: SimpleJob.new)

          Delayed::Job.batch_delay_jobs do
            described_class.enqueue(payload_object: SimpleJob.new)
          end
          expect(Delayed::Job.buffer).to eq({})

          described_class.enqueue(payload_object: SimpleJob.new)
          expect(Delayed::Job.buffer[DEFAULT_QUEUE_NAME].first.size).to eq(1)
        end
        expect(Delayed::Job.buffer).to eq({})
      end
    end

    it 'does not contain anything in buffer outside the transaction' do
      expect { Delayed::Job.batch_delay_jobs { described_class.enqueue(payload_object: SimpleJob.new) } }.
          to_not change { Delayed::Job.buffer }.from({})
    end

    context 'when a transaction has not completed' do
      it 'has not enqueued any messages' do
        Delayed::Job.batch_delay_jobs do
          described_class.enqueue(payload_object: SimpleJob.new)
          described_class.enqueue(payload_object: SimpleJob.new)
          expect(AWS::SQS.new.queues.first.visible_messages).to eq(0)
        end
      end
    end

    context 'when a transaction does not complete' do
      before do
        begin
          Delayed::Job.batch_delay_jobs do
            described_class.enqueue(payload_object: SimpleJob.new)
            described_class.enqueue(payload_object: SimpleJob.new)
            raise
          end
        rescue
          nil
        end
      end
      it 'does not send any messages' do
        expect(AWS::SQS.new.queues.first.visible_messages).to eq(0)
      end

      it 'empties the buffer' do
        expect(Delayed::Job.buffer).to eq({})
      end

      it 'stops buffering' do
        expect(Delayed::Job.buffering?).to eq(false)
      end
    end

    context 'when a transaction completes' do
      before do
        Delayed::Job.batch_delay_jobs do
          described_class.enqueue(payload_object: SimpleJob.new)
          described_class.enqueue(payload_object: SimpleJob.new)
        end
      end
      it 'sends all messages' do
        expect(AWS::SQS.new.queues.first.visible_messages).to eq(2)
      end

      it 'clears the buffer' do
        expect(Delayed::Job.buffer).to eq({})
      end

      it 'does not implicitly buffer later transactions' do
        expect(Delayed::Job.buffering?).to be_falsey
        described_class.enqueue(payload_object: SimpleJob.new)
        expect(Delayed::Job.buffer).to eq({})
        expect(AWS::SQS.new.queues.first.visible_messages).to eq(3)
      end
    end
  end
end
