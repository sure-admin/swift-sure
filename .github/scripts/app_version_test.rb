# frozen_string_literal: true

require "minitest/autorun"
require_relative "app_version"

class AppVersionTest < Minitest::Test
  def test_release_version_comes_from_project_instead_of_build_date
    assert_equal "2026.11", AppVersion.for_build(project: project("2026.11"))
    assert_equal "2027.1", AppVersion.for_build(project: project("2027.1"))
  end

  def test_rejects_app_and_watch_version_mismatch
    assert_raises(ArgumentError) do
      AppVersion.for_build(project: project("2026.11", watch: "2026.11.6"))
    end
  end

  def test_ci_override_must_match_the_upload_version
    assert_equal "2026.11", AppVersion.for_build(project: project("2026.11"), override: "2026.11")
    assert_raises(ArgumentError) do
      AppVersion.for_build(project: project("2026.11"), override: "2026.11.6")
    end
  end

  def test_rejects_invalid_release_versions
    %w[2026 2026.01 2026.11-alpha 2026.11.6.1].each do |invalid|
      assert_raises(ArgumentError) { AppVersion.for_build(project: project(invalid)) }
    end
  end

  def test_project_plists_and_ci_use_the_same_marketing_version
    configuration = JSON.parse(File.read(File.expand_path("../../Project.json", __dir__)))
    version = AppVersion.for_build(project: configuration)
    assert_match(/\A[1-9][0-9]*\.([1-9]|1[0-2])\z/, version)
    ["Sure", "Sure Watch"].each do |name|
      target = configuration.fetch("targets").fetch(name)
      assert_equal version, target.fetch("settings").fetch("base").fetch("MARKETING_VERSION")
      assert_equal "$(MARKETING_VERSION)", target.fetch("info").fetch("properties").fetch("CFBundleShortVersionString")
      refute target.fetch("preBuildScripts", []).any? { |phase| phase.fetch("script").include?("app_version.rb") },
        "A build script must not rewrite the uploaded version"
      refute target.fetch("settings").fetch("base").key?("INFOPLIST_FILE"), "Use the project-generated plist"
    end
  end

  private

  def project(version, watch: version)
    { "targets" => { "Sure" => target(version), "Sure Watch" => target(watch) } }
  end

  def target(version)
    { "settings" => { "base" => { "MARKETING_VERSION" => version } } }
  end
end
