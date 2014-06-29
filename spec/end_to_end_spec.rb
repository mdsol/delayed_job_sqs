require 'spec_helper'

describe 'End-to-End Tests', :sqs do
  describe 'SimpleJob' do
    let(:simple_job) { DelayedJobSqs::SimpleJob.new }
    
    it 'runs in the background' do
      before_runs_count = DelayedJobSqs::SimpleJob.runs
      
      simple_job.delay.perform
      Delayed::Worker.new.work_off
      
      DelayedJobSqs::SimpleJob.runs.should == (before_runs_count + 1)
    end
  end
end