require 'spec_helper'
require 'delayed/backend/shared_spec'
require 'active_record'

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
