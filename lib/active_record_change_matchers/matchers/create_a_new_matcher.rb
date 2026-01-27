# frozen_string_literal: true

module ActiveRecordChangeMatchers
  class CreateANewMatcher
    include RSpec::Matchers::Composable

    def supports_block_expectations?
      true
    end

    def initialize(klass, options = {})
      @klass = klass
      @strategy_key = options[:strategy]
    end

    def with_attributes(attributes)
      @attributes = attributes
      self
    end

    def which(&block)
      @which_block = block
      self
    end

    def which_is_expected_to(matcher)
      @which_matcher = matcher
      self
    end

    def and_return_it
      @should_return_record = true
      self
    end

    def matches?(block)
      @block_return_value = nil
      wrapped_block = proc { @block_return_value = block.call }
      strategy = ActiveRecordChangeMatchers::Strategies.for_key(@strategy_key).new(wrapped_block)
      @created_records = strategy.new_records([@klass])[@klass]

      return false unless @created_records.count == 1

      record = @created_records.first

      @attribute_mismatches = []
      @attributes&.each do |field, value|
        unless values_match?(value, record.public_send(field))
          @attribute_mismatches << [field, value, record.public_send(field)]
        end
      end

      if @attribute_mismatches.none? && @which_block
        begin
          @which_block.call(record)
        rescue RSpec::Expectations::ExpectationNotMetError => e
          @which_failure = e
        end
      end

      if @attribute_mismatches.none? && @which_matcher && !@which_matcher.matches?(record)
        @matcher_failure = @which_matcher.failure_message
      end

      if @should_return_record && @attribute_mismatches.empty? && @which_failure.nil? && @matcher_failure.nil? &&
         !values_match?(record, @block_return_value)
        @return_value_mismatch = { expected: record, actual: @block_return_value }
      end

      @attribute_mismatches.empty? && @which_failure.nil? && @matcher_failure.nil? && @return_value_mismatch.nil?
    end

    def failure_message
      if @created_records.count != 1
        "the block should have created 1 #{@klass}, but created #{@created_records.count}"
      elsif @attribute_mismatches&.any?
        @attribute_mismatches.map do |field, expected, actual|
          expected_description = composable_matcher?(expected) ? expected.description : expected.inspect
          "Expected #{field.inspect} to be #{expected_description}, but was #{actual.inspect}"
        end.join("\n")
      elsif @which_failure
        @which_failure.message
      elsif @return_value_mismatch
        expected = @return_value_mismatch[:expected]
        actual = @return_value_mismatch[:actual]
        "Expected the block to return the created #{@klass}, but it returned #{actual.inspect} instead of #{expected.inspect}"
      else
        @matcher_failure
      end
    end

    def failure_message_when_negated
      if @created_records.count == 1 && @attributes && @attribute_mismatches.none?
        "the block should not have created a #{@klass} with attributes #{format_attributes_hash(@attributes)}, but did"
      elsif @created_records.count == 1 && @which_block && !@which_failure
        "the newly created #{@klass} should have failed an expectation in the given block, but didn't"
      elsif @created_records.count == 1
        "the block should not have created a #{@klass}, but created #{@created_records.count}: #{@created_records.inspect}"
      else
        "the block created a #{@klass} that matched all given criteria"
      end
    end

    def description
      "create a #{@klass}, optionally verifying attributes"
    end

    private

    def composable_matcher?(value)
      value.respond_to?(:failure_message_when_negated)
    end

    def format_attributes_hash(attributes)
      hash = attributes.transform_values { |value| format_value(value) }
      ActiveRecordChangeMatchers.format_hash_for_message(hash)
    end

    def format_value(value)
      composable_matcher?(value) ? value.description : value
    end
  end
end

RSpec::Matchers.define :create_a_new do |klass, *strategy_arg|
  supports_block_expectations
  options = strategy_arg.first.is_a?(Hash) ? strategy_arg.first : {}
  base = ActiveRecordChangeMatchers::CreateANewMatcher.new(klass, options)

  match { |block| base.matches?(block) }
  failure_message { base.failure_message }
  failure_message_when_negated { base.failure_message_when_negated }
  description { base.description }

  chain(:with_attributes) { |*args| base.with_attributes(*args) }
  chain(:which) { |&block| base.which(&block) }
  chain(:which_is_expected_to) { |*args| base.which_is_expected_to(*args) }
  chain(:and_return_it) { base.and_return_it }
end

RSpec::Matchers.alias_matcher :create_a, :create_a_new
RSpec::Matchers.alias_matcher :create_an, :create_a_new
