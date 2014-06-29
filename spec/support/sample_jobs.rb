=begin
require 'fileutils'

# A simple class with a method intended to be run in the background.
class SimpleJob
  TEST_FILE_PATH = File.join(SPEC_DIR, 'support', 'test_file.txt')
  
  def run_job
    FileUtils.touch TEST_FILE_PATH 
  end
    
  # Returns true if the job completed and false otherwise.  This will wait a while for the job to finish.
  # Also has the side-effect of cleaning up artifacts of running the job.
  def completed?
    completed = false
    4.times do 
      completed = File.exists?(TEST_FILE_PATH)
      if completed
        break
      else
        sleep 1
      end
    end

    File.unlink(TEST_FILE_PATH) if File.exists?(TEST_FILE_PATH)
    
    completed
  end
  
  private
  def remove_file
    File.unlink TEST_FILE_PATH
  end
  
end

class ErrorJob
  cattr_accessor :runs; self.runs = 0
  def perform; raise 'did not work'; end
end
=end