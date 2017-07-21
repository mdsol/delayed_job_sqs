source 'http://rubygems.org'

platforms :ruby do
  gem 'sqlite3'
end

group :test do
  gem 'activerecord', (ENV['RAILS_VERSION'] || ['>= 3.0', '< 4.2'])
  
  gem 'fake_sqs', :git => 'https://github.com/mdsol/fake_sqs.git'
end

gemspec
