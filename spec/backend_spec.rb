require 'delayed_job'
require_relative '../lib/delayed/backend/actions.rb'
require_relative '../lib/delayed/serialization/sqs'
require_relative '../lib/delayed/backend/sqs.rb'

describe Delayed::Backend::Sqs::Job do
  before do
    double('Delayed::Backend::Sqs::Job::AWS')
    allow(Delayed::Worker).to receive(:timeout).and_return(5)
  end
  context 'when buffering is set to false' do
    let(:payload) { double('AWS::SQS::ReceivedMessage', body: { timeout: 5, payload_object: { message: 'We test with alacrity' } }) }
    it { expect(Delayed::Backend::Sqs::Job.buffering?).to be_falsey }
    it 'sends messages individually' do
      Delayed::Backend::Sqs::Job.new(payload).save
    end
    it 'does not fill the buffer'
  end
end
