# frozen_string_literal: true

module ActiveRecordChangeMatchers
  class CreateRecordsMatcher
    include ActiveSupport::Inflector
    include RSpec::Matchers::Composable

    def supports_block_expectations?
      true
    end

    def initialize(record_counts, options = {})
      @record_counts = record_counts
      @strategy_key = options[:strategy]
    end

    def with_attributes(attributes)
      if (mismatch = attributes.find { |klass, hashes| hashes.size != @record_counts[klass] })
        mismatched_class, hashes = mismatch
        raise ArgumentError,
              "Specified the block should create #{@record_counts[mismatched_class]} #{mismatched_class}, but provided #{hashes.size} #{mismatched_class} attribute specifications"
      end
      @expected_attributes = attributes
      self
    end

    def which(&block)
      @which_block = block
      self
    end

    def and_return_them
      @should_return_records = true
      self
    end

    def matches?(block)
      @block_return_value = nil
      wrapped_block = proc { @block_return_value = block.call }
      strategy = ActiveRecordChangeMatchers::Strategies.for_key(@strategy_key).new(wrapped_block)
      @new_records = strategy.new_records(@record_counts.keys)

      @incorrect_counts = @new_records.each_with_object({}) do |(klass, new_records), incorrect|
        actual_count = new_records.count
        expected_count = @record_counts[klass]
        incorrect[klass] = { expected: expected_count, actual: actual_count } if actual_count != expected_count
      end

      return false if @incorrect_counts.any?

      if @expected_attributes
        return false unless match_expected_attributes
      end

      run_which_block
      check_return_value if @should_return_records

      @which_failure.nil? && @return_value_mismatch.nil?
    end

    def failure_message
      if @incorrect_counts&.any?
        @incorrect_counts.map do |klass, counts|
          "The block should have created #{count_str(klass, counts[:expected])}, but created #{counts[:actual]}."
        end.join(' ')
      elsif @incorrect_attributes&.any?
        format_attributes_failure_message
      elsif @which_failure
        @which_failure.message
      elsif @return_value_mismatch
        format_return_value_failure_message
      else
        'Unknown error'
      end
    end

    def failure_message_when_negated
      @record_counts.map do |klass, expected_count|
        "The block should not have created #{count_str(klass, expected_count)}, but created #{expected_count}."
      end.join(' ')
    end

    def description
      counts_strs = @record_counts.map { |klass, count| count_str(klass, count) }
      "create #{counts_strs.join(', ')}"
    end

    private

    def count_str(klass, count)
      "#{count} #{klass.name.pluralize(count)}"
    end

    def match_expected_attributes
      @matched_records = Hash.new { |hash, key| hash[key] = [] }
      @all_attributes = Hash.new { |hash, key| hash[key] = [] }
      @incorrect_attributes = @expected_attributes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(klass, expected_attributes), incorrect|
        @all_attributes[klass] = expected_attributes.map(&:keys).flatten.uniq
        expected_attributes.each do |expected_attrs|
          matched_record = (@new_records.fetch(klass) - @matched_records[klass]).find do |record|
            expected_attrs.all? { |k, v| values_match?(v, record.public_send(k)) }
          end
          if matched_record
            @matched_records[klass] << matched_record
          else
            incorrect[klass] << expected_attrs
          end
        end
      end
      @unmatched_records = @matched_records.map do |klass, records|
        [klass, @new_records[klass] - records]
      end.to_h.reject { |_k, v| v.empty? }
      @incorrect_attributes.none?
    end

    def run_which_block
      @which_failure = nil
      return unless @which_block

      @which_block.call(@new_records)
    rescue RSpec::Expectations::ExpectationNotMetError => e
      @which_failure = e
    end

    def check_return_value
      return unless @incorrect_counts.empty? &&
                    (@incorrect_attributes.nil? || @incorrect_attributes.none?) &&
                    @which_failure.nil?

      all_created_records = @new_records.values.flatten
      return_value_array = Array(@block_return_value)
      missing_records = all_created_records.reject do |record|
        return_value_array.any? { |returned| values_match?(record, returned) }
      end
      return unless missing_records.any?

      @return_value_mismatch = {
        expected: all_created_records,
        actual: @block_return_value,
        missing: missing_records
      }
    end

    def format_attributes_failure_message
      "The block should have created:\n" +
        @expected_attributes.map do |klass, attrs|
          "    #{attrs.count} #{klass} with these attributes:\n" +
            attrs.map { |a| "        #{ActiveRecordChangeMatchers.format_hash_for_message(a)}" }.join("\n")
        end.join("\n") +
        "\nDiff:" +
        @incorrect_attributes.map do |klass, attrs|
          "\n    Missing #{attrs.count} #{klass} with these attributes:\n" +
            attrs.map { |a| "        #{ActiveRecordChangeMatchers.format_hash_for_message(a)}" }.join("\n")
        end.join("\n") +
        @unmatched_records.map do |klass, records|
          "\n    Extra #{records.count} #{klass} with these attributes:\n" +
            records.map do |r|
              attrs = @all_attributes[klass].each_with_object({}) { |attr, h| h[attr] = r.public_send(attr) }
              "        #{ActiveRecordChangeMatchers.format_hash_for_message(attrs)}"
            end.join("\n")
        end.join("\n")
    end

    def format_return_value_failure_message
      missing = @return_value_mismatch[:missing]
      expected = @return_value_mismatch[:expected]
      actual = @return_value_mismatch[:actual]
      'Expected the block to return the created records, but it did not return all of them. ' \
        "Missing records: #{missing.map(&:inspect).join(', ')}. " \
        "Expected all of: #{expected.map(&:inspect).join(', ')}, " \
        "but got: #{actual.inspect}"
    end
  end
end

RSpec::Matchers.define :create_records do |record_counts, *strategy_arg|
  supports_block_expectations
  options = strategy_arg.first.is_a?(Hash) ? strategy_arg.first : {}
  base = ActiveRecordChangeMatchers::CreateRecordsMatcher.new(record_counts, options)

  match { |block| base.matches?(block) }
  failure_message { base.failure_message }
  failure_message_when_negated { base.failure_message_when_negated }
  description { base.description }

  chain(:with_attributes) { |*args| base.with_attributes(*args) }
  chain(:which) { |&block| base.which(&block) }
  chain(:and_return_them) { base.and_return_them }
end

RSpec::Matchers.alias_matcher :create, :create_records
