# This module contains our own sample jobs used for testing purposes.  These are available in addition to those used in
# the dj sqs backend shared examples.
module DelayedJobSqs
  class SimpleJob
    cattr_accessor :runs; self.runs = 0
    def perform; @@runs += 1; end
  end
end
