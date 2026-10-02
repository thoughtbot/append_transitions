# frozen_string_literal: true

require_relative "lib/append_transitions/version"

Gem::Specification.new do |spec|
  spec.name = "append_transitions"
  spec.version = AppendTransitions::VERSION
  spec.authors = ["Thiago A. Silva"]
  spec.email = ["thiagoaraujos@gmail.com"]

  spec.summary = "Append-only state transitions for ActiveRecord with safe concurrency and simple validation."
  spec.homepage = "https://github.com/thoughtbot/append_transitions"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile gemfiles/ .github/ .gitignore test/ .standard.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.0"
end
