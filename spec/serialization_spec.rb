require_relative '../lib/delayed/serialization/sqs'

describe(DelayedJobSqs::Document) do

  it 'serializes and deserializes an array' do
    array = ['a', 'b']
    serialized_array = described_class.sqs_safe_json_dump(array)
    deserialized_array = described_class.sqs_safe_json_load(serialized_array)
    expect(deserialized_array).to eq(array)
  end

  it 'serializes and deserializes a hash' do
    hash = { 'a' => 'b' }
    serialized_hash = described_class.sqs_safe_json_dump(hash)
    deserialized_hash = described_class.sqs_safe_json_load(serialized_hash)
    expect(deserialized_hash).to eq(hash)
  end

  it 'serializes and deserializes a large array using compression' do
    array = ['a', 'b'] * 2**18
    serialized_array = described_class.sqs_safe_json_dump(array)
    expect(serialized_array.bytesize).to be < 2**18
    deserialized_array = described_class.sqs_safe_json_load(serialized_array)
    expect(deserialized_array).to eq(array)
  end

end
