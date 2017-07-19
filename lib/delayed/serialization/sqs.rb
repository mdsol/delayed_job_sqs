# encoding: utf-8

require 'zlib'
require 'json' unless defined?(JSON)
require 'base64'

module DelayedJobSqs
  module Document
    MAX_SQS_MESSAGE_SIZE_IN_BYTES = 2**18

    def self.sqs_safe_json_dump(obj)
      json = JSON.dump(obj)
      if json.bytesize >= MAX_SQS_MESSAGE_SIZE_IN_BYTES
        JSON.dump(dj_compressed_document: compress(json))
      else
        json
      end
    end

    def self.sqs_safe_json_load(json)
      obj = JSON.load(json)
      if obj.is_a?(Hash) && obj.key?('dj_compressed_document')
        JSON.load(decompress(obj['dj_compressed_document']))
      else
        obj
      end
    end

    def self.compress(string)
      Base64.encode64(Zlib::Deflate.deflate(string))
    end

    def self.decompress(string)
      Zlib::Inflate.inflate(Base64.decode64(string))
    end

  end
end
