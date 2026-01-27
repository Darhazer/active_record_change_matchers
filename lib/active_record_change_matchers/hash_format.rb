# frozen_string_literal: true

# Ruby 3.4 changed Hash#inspect (symbol keys use {key: val}, other keys use "key" => val with spaces).
# This helper produces a stable format so error messages look the same on 3.3 and 3.4.
module ActiveRecordChangeMatchers
  def self.format_hash_for_message(hash)
    "{#{hash.map { |k, v| "#{k.inspect}=>#{v.inspect}" }.join(', ')}}"
  end
end
