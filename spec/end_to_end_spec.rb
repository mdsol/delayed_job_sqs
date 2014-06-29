require 'spec_helper'

describe 'End-to-End Tests', :sqs do
  describe 'SimpleJob' do
    let(:simple_job) { DelayedJobSqs::SimpleJob.new }
    
    it 'delays a single simple job successfully' do
      before_runs_count = DelayedJobSqs::SimpleJob.runs
      
      simple_job.delay.perform
      Delayed::Worker.new.work_off
      
      DelayedJobSqs::SimpleJob.runs.should == (before_runs_count + 1)
    end
    
    it 'delays multiple simple jobs successfully' do
      before_runs_count = DelayedJobSqs::SimpleJob.runs
      
      n = 2
      n.times{ simple_job.delay.perform }
      Delayed::Worker.new.work_off
      
      DelayedJobSqs::SimpleJob.runs.should == (before_runs_count + n)
    end
  end
end
