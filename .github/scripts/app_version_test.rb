# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "app_version"

class AppVersionTest < Minitest::Test
  def test_date_version_without_leading_zeroes
    assert_equal "2026.11.6", AppVersion.for_build(time: Time.utc(2026, 11, 6, 12))
    assert_equal "2027.1.1", AppVersion.for_build(time: Time.utc(2027, 1, 1, 12))
    assert_equal "2028.2.29", AppVersion.for_build(time: Time.utc(2028, 2, 29, 12))
  end

  def test_uses_release_calendar_across_utc_date_boundary
    assert_equal "2026.11.6", AppVersion.for_build(time: Time.utc(2026, 11, 7, 2, 30))
    assert_equal "2026.7.6", AppVersion.for_build(time: Time.utc(2026, 7, 7, 6, 30))
    assert_equal "2026.7.7", AppVersion.for_build(time: Time.utc(2026, 7, 7, 7, 30))
  end

  def test_ci_can_freeze_version_across_midnight
    assert_equal "2026.11.6", AppVersion.for_build(time: Time.utc(2026, 11, 7), override: "2026.11.6")
    assert_raises(ArgumentError) { AppVersion.for_build(override: "2026.11.6-alpha") }
  end

  def test_writes_only_the_derived_plist_and_preserves_build_number
    Dir.mktmpdir do |dir|
      source = File.join(dir, "source.plist")
      destination = File.join(dir, "derived", "Info.plist")
      original = '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>$(MARKETING_VERSION)</string><key>CFBundleVersion</key><string>42</string></dict></plist>'
      File.write(source, original)
      AppVersion.prepare_plist(source, destination, version: "2026.11.6")
      assert_equal original, File.read(source)
      assert_equal "2026.11.6", IO.popen(["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleShortVersionString", destination], &:read).strip
      assert_equal "42", IO.popen(["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleVersion", destination], &:read).strip
      assert_raises(ArgumentError) { AppVersion.prepare_plist(source, source, version: "2026.11.6") }
    end
  end
end
