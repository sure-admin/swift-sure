# frozen_string_literal: true

require "fileutils"

module AppVersion
  def self.for_build(time: Time.now, override: nil)
    version = if override.to_s.empty?
      # Use one release calendar across developer machines and CI runners.
      IO.popen([{ "TZ" => "America/Los_Angeles" }, "/bin/date", "-r", time.to_i.to_s, "+%Y.%-m.%-d"], &:read).strip
    else
      override
    end
    unless /\A[1-9][0-9]*\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z/.match?(version)
      raise ArgumentError, "App version must contain three dot-separated integers"
    end
    version
  end

  def self.prepare_plist(source, destination, version:)
    raise ArgumentError, "Versioned plist must be a derived file" if File.expand_path(source) == File.expand_path(destination)

    FileUtils.mkdir_p(File.dirname(destination))
    FileUtils.cp(source, destination)
    success = system("/usr/libexec/PlistBuddy", "-c", "Set :CFBundleShortVersionString #{version}", destination)
    raise "Could not set app version" unless success
  end
end

if $PROGRAM_NAME == __FILE__
  version = AppVersion.for_build(override: ENV["SURE_APP_VERSION"])
  case ARGV.length
  when 0 then puts version
  when 2 then AppVersion.prepare_plist(*ARGV, version: version)
  else abort "Usage: app_version.rb [source.plist derived.plist]"
  end
end
