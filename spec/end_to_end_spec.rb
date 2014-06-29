require 'spec_helper'

describe 'End-to-End Tests', :sqs do
  describe 'SimpleJob' do
    let(:simple_job) { SimpleJob.new }
    
    it 'runs in the background' do
      simple_job.delay.run_job
      Delayed::Worker.new.work_off
      simple_job.completed?.should be_true
    end
  end
end