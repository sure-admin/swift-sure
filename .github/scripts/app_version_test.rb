# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "app_version"

class AppVersionTest < Minitest::Test
  def test_monthly_versions_without_leading_zeroes
    assert_equal "2026.11", AppVersion.for_build(time: Time.utc(2026, 11, 6, 12))
    assert_equal "2026.11", AppVersion.for_build(time: Time.utc(2026, 11, 30, 12))
    assert_equal "2027.1", AppVersion.for_build(time: Time.utc(2027, 1, 1, 12))
    assert_equal "2028.2", AppVersion.for_build(time: Time.utc(2028, 2, 29, 12))
  end

  def test_uses_release_calendar_across_month_and_year_boundaries
    assert_equal "2026.10", AppVersion.for_build(time: Time.utc(2026, 11, 1, 6, 30))
    assert_equal "2026.11", AppVersion.for_build(time: Time.utc(2026, 11, 1, 7, 30))
    assert_equal "2026.12", AppVersion.for_build(time: Time.utc(2027, 1, 1, 7, 30))
    assert_equal "2027.1", AppVersion.for_build(time: Time.utc(2027, 1, 1, 8, 30))
  end

  def test_ios_and_watch_share_monthly_versions_while_mac_keeps_daily_versions
    time = Time.utc(2026, 11, 7, 12)
    %w[iphoneos iphonesimulator watchos watchsimulator].each do |platform|
      assert_equal "2026.11", AppVersion.for_build(time: time, platform: platform)
    end
    assert_equal "2026.11.7", AppVersion.for_build(time: time, platform: "macosx")
  end

  def test_ci_can_freeze_monthly_and_existing_daily_versions
    assert_equal "2026.11", AppVersion.for_build(time: Time.utc(2026, 12, 2), override: "2026.11")
    assert_equal "2026.11.6", AppVersion.for_build(override: "2026.11.6")
    %w[2026 2026.01 2026.11-alpha 2026.11.6.1].each do |invalid|
      assert_raises(ArgumentError) { AppVersion.for_build(override: invalid) }
    end
  end

  def test_writes_only_the_derived_plist_and_preserves_build_number
    Dir.mktmpdir do |dir|
      source = File.join(dir, "source.plist")
      destination = File.join(dir, "derived", "Info.plist")
      original = '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>$(MARKETING_VERSION)</string><key>CFBundleVersion</key><string>42</string></dict></plist>'
      File.write(source, original)
      AppVersion.prepare_plist(source, destination, version: "2026.11")
      assert_equal original, File.read(source)
      assert_equal "2026.11", IO.popen(["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleShortVersionString", destination], &:read).strip
      assert_equal "42", IO.popen(["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleVersion", destination], &:read).strip
      assert_raises(ArgumentError) { AppVersion.prepare_plist(source, source, version: "2026.11") }
    end
  end
end
