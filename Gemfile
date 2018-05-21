source 'http://rubygems.org'

platforms :ruby do
  gem 'sqlite3'
end

group :test do
  gem 'activerecord', (ENV['RAILS_VERSION'] || ['>= 3.0', '< 4.2'])
  gem 'fake_sqs', git: 'git@github.com:mdsol/fake_sqs.git', branch: 'feature/aws_sdk_v3'
end

gemspec

group :development, :test do
  gem 'pry'
  gem 'pry-nav'
end
