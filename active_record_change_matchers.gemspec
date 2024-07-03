# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "active_record_change_matchers/version"

Gem::Specification.new do |spec|
  spec.name          = "active_record_change_matchers"
  spec.version       = ActiveRecordChangeMatchers::VERSION
  spec.authors       = ["Maxim Krizhanovski", "Nathan Wallace"]
  spec.email         = ["maxim.krizhanovski@hey.com"]

  spec.summary       = %q{Additional RSpec custom matchers for ActiveRecord}
  spec.description   = %q{This gem adds custom block expectation matchers for RSpec, such as `expect { ... }.to create_a_new(User)`}
  spec.homepage      = "https://github.com/Darhazer/active_record_change_matchers"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 1.9.3"

  spec.add_dependency "activerecord", ">= 3.2.0"
  spec.add_dependency "rspec-expectations", ">= 3.0.0"

  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.6"
  spec.add_development_dependency "pry", "~> 0.10"
  spec.add_development_dependency "sqlite3", "~> 1.3"
  spec.add_development_dependency "database_cleaner", "~> 1.6"
  spec.add_development_dependency "standalone_migrations", "~> 5.2"
  spec.add_development_dependency "timecop", "~> 0.9"
end
