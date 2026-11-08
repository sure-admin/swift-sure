# frozen_string_literal: true

require "json"

module AppVersion
  def self.for_build(project: nil, override: nil)
    project ||= JSON.parse(File.read(File.expand_path("../../Project.json", __dir__)))
    versions = ["Sure", "Sure Watch"].map do |target|
      project.fetch("targets").fetch(target).fetch("settings").fetch("base").fetch("MARKETING_VERSION")
    end
    raise ArgumentError, "App and Watch marketing versions must match" unless versions.uniq.length == 1

    version = versions.first
    unless /\A[1-9][0-9]*\.(0|[1-9][0-9]*)(?:\.(0|[1-9][0-9]*))?\z/.match?(version)
      raise ArgumentError, "App version must contain two or three dot-separated integers"
    end
    if !override.to_s.empty? && override != version
      raise ArgumentError, "SURE_APP_VERSION must match MARKETING_VERSION in Project.json"
    end
    version
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: app_version.rb" unless ARGV.empty?
  puts AppVersion.for_build(override: ENV["SURE_APP_VERSION"])
end
