RSpec::Matchers.define :create_a_new do |klass|
  supports_block_expectations

  description do
    "create a #{klass}, optionally verifying attributes"
  end

  chain(:with_attributes) do |attributes|
    @attributes = attributes
  end

  chain(:which) do |&block|
    @which_block = block
  end

  chain(:which_is_expected_to) do |matcher|
    @which_matcher = matcher
  end

  chain(:and_return_it) do
    @should_return_record = true
  end

  match do |options = {}, block|
    # Capture the return value of the block
    @block_return_value = nil
    wrapped_block = proc do
      @block_return_value = block.call
    end

    fetching_strategy =
      ActiveRecordChangeMatchers::Strategies.for_key(options[:strategy]).new(wrapped_block)

    @created_records = fetching_strategy.new_records([klass])[klass]

    return false unless @created_records.count == 1 # ? this shouldn't be necessary for all strategies...

    record = @created_records.first

    @attribute_mismatches = []

    @attributes && @attributes.each do |field, value|
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

    # Verify return value if requested
    if @should_return_record && @attribute_mismatches.empty? && @which_failure.nil? && @matcher_failure.nil? && !values_match?(
      record, @block_return_value
    )
      @return_value_mismatch = { expected: record, actual: @block_return_value }
    end

    @attribute_mismatches.empty? && @which_failure.nil? && @matcher_failure.nil? && @return_value_mismatch.nil?
  end

  failure_message do
    if @created_records.count != 1
      "the block should have created 1 #{klass}, but created #{@created_records.count}"
    elsif @attribute_mismatches.any?
      @attribute_mismatches.map do |field, expected, actual|
        expected_description = is_composable_matcher?(expected) ? expected.description : expected.inspect
        "Expected #{field.inspect} to be #{expected_description}, but was #{actual.inspect}"
      end.join("\n")
    elsif @which_failure
      @which_failure.message
    elsif @return_value_mismatch
      expected = @return_value_mismatch[:expected]
      actual = @return_value_mismatch[:actual]
      "Expected the block to return the created #{klass}, but it returned #{actual.inspect} instead of #{expected.inspect}"
    else
      @matcher_failure
    end
  end

  failure_message_when_negated do
    if @created_records.count == 1 && @attributes && @attribute_mismatches.none?
      "the block should not have created a #{klass} with attributes #{format_attributes_hash(@attributes)}, but did"
    elsif @created_records.count == 1 && @which_block && !@which_failure
      "the newly created #{klass} should have failed an expectation in the given block, but didn't"
    elsif @created_records.count == 1
      "the block should not have created a #{klass}, but created #{@created_records.count}: #{@created_records.inspect}"
    else
      "the block created a #{klass} that matched all given criteria"
    end
  end

  def is_composable_matcher?(value)
    value.respond_to?(:failure_message_when_negated)
  end

  def format_attributes_hash(attributes)
    hash = attributes.transform_values { |value| format_value(value) }
    ActiveRecordChangeMatchers.format_hash_for_message(hash)
  end

  def format_value(value)
    is_composable_matcher?(value) ? value.description : value
  end
end

RSpec::Matchers.alias_matcher :create_a,  :create_a_new
RSpec::Matchers.alias_matcher :create_an, :create_a_new
