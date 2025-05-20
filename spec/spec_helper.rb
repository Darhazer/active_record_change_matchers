$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "active_record_change_matchers"
require "sqlite3"
require "database_cleaner/active_record"
require "pry"
require "timecop"
require "yaml"

db_config = YAML::load(File.open("db/config.yml")).fetch("test")
ActiveRecord::Base.establish_connection(db_config)


Dir[File.join(File.dirname(__FILE__), "support", "**", "*.rb")].each {|f| require f }

RSpec.configure do |config|
  config.include ActiveRecordChangeMatchers::SpecUtilities
  config.before(:suite) do
    DatabaseCleaner[:active_record].strategy = :transaction
    DatabaseCleaner[:active_record].clean_with(:truncation)
  end
  config.around(:each) do |example|
    DatabaseCleaner[:active_record].cleaning do
      example.run
    end
  end
end
