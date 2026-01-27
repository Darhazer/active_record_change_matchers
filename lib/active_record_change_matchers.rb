require "rspec/expectations"
require "active_record"

require_relative "active_record_change_matchers/hash_format"
Dir[File.dirname(__FILE__) + "/active_record_change_matchers/**/*.rb"].each {|file| require file }

module ActiveRecordChangeMatchers
end
