require "rails_helper"

RSpec.describe "skill symbol references" do
  # Symbols from gems or test-only helpers cannot be resolved from the application
  # autoload paths. Keep every exception documented here rather than weakening the
  # check for all skill documentation.
  SYMBOL_REFERENCE_ALLOWLIST = {
    "XRows.call" => "Generic row-parser placeholder in the detached-run recipe.",
    "SourceClass.method" => "Generic source-class placeholder in the detached-run recipe.",
    "Model.enum_name" => "Generic Active Record model placeholder in the review checklist.",
    "Klass.new" => "Generic dispatch-table class placeholder in the stage-pipeline recipe."
  }.freeze

  SYMBOL_TOKEN = /(?<![A-Za-z0-9_:<])((?:[A-Z][A-Za-z0-9_]*::)*[A-Z][A-Za-z0-9_]*)([#.])([a-z_][A-Za-z0-9_]*[!?=]?)(?:\([^`]*\))?/.freeze

  def skill_files
    Dir.glob(".agents/skills/*/{SKILL.md,assets/*.md}").sort
  end

  def symbol_references(path)
    File.read(path).scan(/`([^`]+)`/).flatten.flat_map do |span|
      span.scan(SYMBOL_TOKEN).filter_map do |constant_name, separator, method_name|
        token = "#{constant_name}#{separator}#{method_name}"
        next if constant_name.start_with?("X::") || span.include?("...") || documentation_filename?(token)

        token
      end
    end
  end

  def documentation_filename?(token)
    token.match?(/\A[A-Z][A-Z0-9_]*\.[a-z0-9]+\z/)
  end

  def resolves?(token)
    constant_name, separator, method_name = token.match(/\A(.+)([#.])([^#.]+)\z/).captures
    constant = constant_name.safe_constantize
    return false unless constant

    if separator == "#"
      instance_method?(constant, method_name)
    else
      constant.respond_to?(method_name, true)
    end
  end

  def instance_method?(constant, method_name)
    return false unless constant.is_a?(Module)

    if constant.is_a?(Class) && constant <= ActiveRecord::Base
      constant.define_attribute_methods
      return true if active_record_method?(constant, method_name)
    end

    (constant.instance_methods(true) + constant.private_instance_methods(true)).map(&:to_s).include?(method_name)
  end

  def active_record_method?(model, method_name)
    attribute_names = model.attribute_names
    association_names = model.reflect_on_all_associations.map { |association| association.name.to_s }
    enum_names = model.defined_enums.flat_map { |name, values| [name, *values.keys] }
    generated_names = attribute_names + association_names + enum_names

    generated_names.any? do |name|
      [name, "#{name}?", "#{name}=", "#{name}_ids", "#{name}_ids="].include?(method_name)
    end
  end

  it "references resolvable application symbols" do
    missing_symbols = skill_files.flat_map do |path|
      symbol_references(path).uniq.filter_map do |token|
        "#{path}: #{token}" unless SYMBOL_REFERENCE_ALLOWLIST.key?(token) || resolves?(token)
      end
    end

    expect(missing_symbols).to be_empty, "Missing skill symbols:\n#{missing_symbols.join("\n")}"
  end
end
