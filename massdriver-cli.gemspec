# frozen_string_literal: true

require_relative "lib/massdriver/version"

Gem::Specification.new do |spec|
  spec.name = "massdriver-cli"
  spec.version = Massdriver::VERSION
  spec.authors = ["David Cox Jr"]
  spec.email = ["david@printavo.com"]

  spec.summary = "A wrapper around mass cli with configurable options"
  spec.description = "A wrapper around mass cli with configurable options"
  spec.homepage = "https://github.com/trackersystems/massdriver-cli"
  spec.required_ruby_version = ">= 2.7.8"

  spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/trackersystems/massdriver-cli"
  spec.metadata["changelog_uri"] = "https://github.com/trackersystems/massdriver-cli"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  spec.add_dependency "thor"
end

