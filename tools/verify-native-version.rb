# Parse the source configuration before Xcode consumes the generated project.
# An existing pbxproj can build successfully even when project.yml is malformed.
require 'yaml'

begin
  project = YAML.safe_load(File.read(ARGV.fetch(0)))
  targets = project.fetch('targets')
  versions = %w[Fotty FottyLiveActivityExtension].map do |name|
    base = targets.fetch(name).fetch('settings').fetch('base')
    [base.fetch('MARKETING_VERSION').to_s, base.fetch('CURRENT_PROJECT_VERSION').to_s]
  end
  marketing, build = versions.first
  unless marketing.match?(/\A[0-9]+\.[0-9]+\.[0-9]+\z/) && build.match?(/\A[1-9][0-9]*\z/)
    raise 'Invalid native version format'
  end
  raise 'App and extension source versions differ' unless versions.uniq.length == 1

  xcode = File.read(ARGV.fetch(1))
  actual_marketing = xcode.scan(/^\s*MARKETING_VERSION = ([^;]+);/).flatten
  actual_build = xcode.scan(/^\s*CURRENT_PROJECT_VERSION = ([^;]+);/).flatten
  unless actual_marketing.length == 4 && actual_build.length == 4 &&
         actual_marketing.uniq == [marketing] && actual_build.uniq == [build]
    raise 'App and extension Debug/Release versions differ from source configuration'
  end
  puts "Native versions coherent: #{marketing} (#{build}) across source and four Xcode configurations."
rescue StandardError => error
  warn "Native version check failed: #{error.message}"
  exit 1
end
