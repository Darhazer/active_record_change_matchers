# frozen_string_literal: true

RSpec::Matchers.define :create_associated do |scope_or_counts|
  include ActiveSupport::Inflector

  supports_block_expectations

  def normalize_scope_counts(value)
    case value
    when Hash
      value
    else
      { value => 1 }
    end
  end

  def scope_counts
    @scope_counts ||= normalize_scope_counts(expected)
  end

  def scopes
    scope_counts.keys
  end

  def single_scope?
    scope_counts.size == 1
  end

  def single_record?
    single_scope? && scope_counts.values.first == 1
  end

  description do
    counts_strs = scope_counts.map { |scope, count| count_str(scope.klass, count) }
    "create #{counts_strs.join(', ')} within the given scope(s)"
  end

  chain(:with_attributes) do |attributes|
    @expected_attributes = normalize_expected_attributes(attributes)
    validate_attributes_count!
  end

  chain(:which) do |&block|
    @which_block = block
  end

  chain(:and_return_it) do
    raise ArgumentError, '`and_return_it` only applies when expecting exactly one record' unless single_record?

    @should_return_records = true
  end

  chain(:and_return_them) do
    @should_return_records = true
  end

  match do |options = {}, block|
    @block_return_value = nil
    wrapped_block = proc { @block_return_value = block.call }

    column = ActiveRecordChangeMatchers::Config.id_column_name

    ids_before = scopes.index_with { |scope| scope.maximum(column) || 0 }
    wrapped_block.call
    @new_records = scopes.index_with do |scope|
      max_before = ids_before[scope]
      scope.where("#{scope.klass.quoted_table_name}.#{scope.klass.connection.quote_column_name(column)} > ?",
                  max_before).to_a
    end

    @incorrect_counts = @new_records.each_with_object({}) do |(scope, records), incorrect|
      expected_count = scope_counts[scope]
      actual_count = records.size
      incorrect[scope] = { expected: expected_count, actual: actual_count } if actual_count != expected_count
    end

    return false if @incorrect_counts.any?

    if @expected_attributes
      @matched_records = Hash.new { |h, k| h[k] = [] }
      @all_attributes = Hash.new { |h, k| h[k] = [] }
      @incorrect_attributes = @expected_attributes.each_with_object(Hash.new do |h, k|
        h[k] = []
      end) do |(scope, expected_attrs_list), incorrect|
        records = @new_records[scope]
        @all_attributes[scope] = expected_attrs_list.map(&:keys).flatten.uniq
        expected_attrs_list.each do |expected_attrs|
          matched = (records - @matched_records[scope]).find do |record|
            expected_attrs.all? { |k, v| values_match?(v, record.public_send(k)) }
          end
          if matched
            @matched_records[scope] << matched
          else
            incorrect[scope] << expected_attrs
          end
        end
      end
      @unmatched_records = scopes.to_h do |scope|
        [scope, @new_records[scope] - @matched_records[scope]]
      end.reject { |_, records| records.empty? }
      return false if @incorrect_attributes.any? { |_, list| list.any? }
    end

    new_records_by_klass = @new_records.transform_keys(&:klass)
    begin
      @which_block&.call(new_records_by_klass)
    rescue RSpec::Expectations::ExpectationNotMetError => e
      @which_failure = e
    end

    if @should_return_records && @incorrect_counts.empty? && (@incorrect_attributes.nil? || @incorrect_attributes.none? do |_, l|
      l.any?
    end) && @which_failure.nil?
      all_created = @new_records.values.flatten
      returned = Array(@block_return_value)
      missing = all_created.reject { |r| returned.any? { |o| values_match?(r, o) } }
      if single_record? && missing.any?
        @return_value_mismatch = { expected: all_created.first, actual: @block_return_value }
      elsif missing.any?
        @return_value_mismatch = { expected: all_created, actual: @block_return_value, missing: missing }
      end
    end

    @which_failure.nil? && @return_value_mismatch.nil?
  end

  failure_message do
    if @incorrect_counts&.any?
      @incorrect_counts.map do |scope, counts|
        "The block should have created #{count_str(scope.klass,
                                                   counts[:expected])} within the scope, but created #{counts[:actual]}."
      end.join(' ')
    elsif @incorrect_attributes&.any? { |_, list| list.any? }
      "The block should have created:\n" +
        @expected_attributes.map do |scope, attrs|
          "    #{attrs.count} #{scope.klass.name} with these attributes:\n" +
            attrs.map { |a| "        #{ActiveRecordChangeMatchers.format_hash_for_message(a)}" }.join("\n")
        end.join("\n") +
        "\nDiff:" +
        @incorrect_attributes.map do |scope, attrs|
          next if attrs.empty?

          "\n    Missing #{attrs.count} #{scope.klass.name} with these attributes:\n" +
            attrs.map { |a| "        #{ActiveRecordChangeMatchers.format_hash_for_message(a)}" }.join("\n")
        end.compact.join("\n") +
        @unmatched_records.map do |scope, records|
          "\n    Extra #{records.count} #{scope.klass.name} with these attributes:\n" +
            records.map do |r|
              attrs = @all_attributes[scope].each_with_object({}) { |attr, h| h[attr] = r.public_send(attr) }
              "        #{ActiveRecordChangeMatchers.format_hash_for_message(attrs)}"
            end.join("\n")
        end.join("\n")
    elsif @which_failure
      @which_failure.message
    elsif @return_value_mismatch
      if single_record?
        "Expected the block to return the created #{scopes.first.klass.name}, but it returned #{@return_value_mismatch[:actual].inspect} instead of #{@return_value_mismatch[:expected].inspect}"
      else
        missing = @return_value_mismatch[:missing]
        'Expected the block to return the created records, but it did not return all of them. ' \
          "Missing records: #{missing.map(&:inspect).join(', ')}. " \
          "Expected all of: #{@return_value_mismatch[:expected].map(&:inspect).join(', ')}, " \
          "but got: #{@return_value_mismatch[:actual].inspect}"
      end
    else
      'Unknown error'
    end
  end

  failure_message_when_negated do
    scope_counts.map do |scope, expected_count|
      "The block should not have created #{count_str(scope.klass,
                                                     expected_count)} within the scope, but created #{expected_count}."
    end.join(' ')
  end

  def count_str(klass, count)
    "#{count} #{klass.name.pluralize(count)}"
  end

  def normalize_expected_attributes(attributes)
    return {} if attributes.nil?

    if single_scope? && attributes.is_a?(Hash) && attributes.keys.all? { |k| k.is_a?(Symbol) || k.is_a?(String) }
      { scopes.first => [attributes] }
    elsif single_scope? && attributes.is_a?(Array)
      { scopes.first => attributes }
    else
      attributes
    end
  end

  def validate_attributes_count!
    return unless @expected_attributes

    @expected_attributes.each do |scope, hashes|
      expected_count = scope_counts[scope]
      next unless expected_count && hashes.size != expected_count

      raise ArgumentError,
            "Specified the block should create #{expected_count} #{scope.klass.name} within the scope, but provided #{hashes.size} attribute specifications"
    end
  end
end
