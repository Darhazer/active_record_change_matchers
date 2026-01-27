RSpec::Matchers.define :create_records do |record_counts|
  include ActiveSupport::Inflector

  supports_block_expectations

  description do
    counts_strs = record_counts.map { |klass, count| count_str(klass, count) }
    "create #{counts_strs.join(', ')}"
  end

  chain(:with_attributes) do |attributes|
    if mismatch = attributes.find { |klass, hashes| hashes.size != record_counts[klass] }
      mismatched_class, hashes = mismatch
      raise ArgumentError,
            "Specified the block should create #{record_counts[mismatched_class]} #{mismatched_class}, but provided #{hashes.size} #{mismatched_class} attribute specifications"
    end
    @expected_attributes = attributes
  end

  chain(:which) do |&block|
    @which_block = block
  end

  chain(:and_return_them) do
    @should_return_records = true
  end

  match do |options = {}, block|
    # Capture the return value of the block
    @block_return_value = nil
    wrapped_block = proc do
      @block_return_value = block.call
    end

    fetching_strategy =
      ActiveRecordChangeMatchers::Strategies.for_key(options[:strategy]).new(wrapped_block)

    @new_records = fetching_strategy.new_records(record_counts.keys)

    @incorrect_counts =
      @new_records.each_with_object({}) do |(klass, new_records), incorrect|
        actual_count = new_records.count
        expected_count = record_counts[klass]
        incorrect[klass] = { expected: expected_count, actual: actual_count } if actual_count != expected_count
      end

    return false if @incorrect_counts.any?

    if @expected_attributes
      @matched_records = Hash.new { |hash, key| hash[key] = [] }
      @all_attributes = Hash.new { |hash, key| hash[key] = [] }
      @incorrect_attributes =
        @expected_attributes.each_with_object(Hash.new do |hash, key|
          hash[key] = []
        end) do |(klass, expected_attributes), incorrect|
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
      end.to_h.reject { |k, v| v.empty? }
      return false if @incorrect_attributes.any?
    end

    begin
      @which_block && @which_block.call(@new_records)
    rescue RSpec::Expectations::ExpectationNotMetError => e
      @which_failure = e
    end

    # Verify return value if requested
    if @should_return_records && @incorrect_counts.empty? && (!@incorrect_attributes || @incorrect_attributes.empty?) && @which_failure.nil?
      all_created_records = @new_records.values.flatten
      return_value_array = Array(@block_return_value)

      missing_records = all_created_records.reject do |record|
        return_value_array.any? { |returned| values_match?(record, returned) }
      end

      if missing_records.any?
        @return_value_mismatch = {
          expected: all_created_records,
          actual: @block_return_value,
          missing: missing_records
        }
      end
    end

    @which_failure.nil? && @return_value_mismatch.nil?
  end

  failure_message do
    if @incorrect_counts.present?
      @incorrect_counts.map do |klass, counts|
        "The block should have created #{count_str(klass, counts[:expected])}, but created #{counts[:actual]}."
      end.join(' ')
    elsif @incorrect_attributes.present?
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
              attrs = @all_attributes[klass].each_with_object({}) { |attr, attrs| attrs[attr] = r.public_send(attr) }
              "        #{ActiveRecordChangeMatchers.format_hash_for_message(attrs)}"
            end.join("\n")
        end.join("\n")
    elsif @which_failure
      @which_failure
    elsif @return_value_mismatch
      missing = @return_value_mismatch[:missing]
      expected = @return_value_mismatch[:expected]
      actual = @return_value_mismatch[:actual]
      'Expected the block to return the created records, but it did not return all of them. ' \
      "Missing records: #{missing.map(&:inspect).join(', ')}. " \
      "Expected all of: #{expected.map(&:inspect).join(', ')}, " \
      "but got: #{actual.inspect}"
    else
      'Unknown error'
    end
  end

  failure_message_when_negated do
    record_counts.map do |klass, expected_count|
      "The block should not have created #{count_str(klass, expected_count)}, but created #{expected_count}."
    end.join(' ')
  end

  def count_str(klass, count)
    "#{count} #{klass.name.pluralize(count)}"
  end
end

RSpec::Matchers.alias_matcher :create, :create_records
