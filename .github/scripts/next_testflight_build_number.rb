# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "uri"

module TestFlightBuildNumber
  module_function

  def next_number(existing_versions, offset:)
    raise ArgumentError, "offset must be positive" unless offset.positive?

    latest = existing_versions.map { |version| components(version) }.max
    latest_major = latest&.first || 0
    (latest_major + offset).to_s
  end

  def components(version)
    value = version.to_s
    unless value.match?(/\A\d+(?:\.\d+){0,2}\z/)
      raise ArgumentError, "invalid App Store build number: #{value.inspect}"
    end

    value.split(".").map(&:to_i).fill(0, value.count(".") + 1...3)
  end
end

class AppStoreConnectClient
  API_BASE_URL = "https://api.appstoreconnect.apple.com"

  def initialize(issuer_id:, key_id:, private_key_path:)
    @issuer_id = issuer_id
    @key_id = key_id
    @private_key = OpenSSL::PKey.read(File.read(private_key_path))
  end

  def build_versions(bundle_id:, marketing_version:)
    app_response = get(
      "/v1/apps",
      "filter[bundleId]" => bundle_id,
      "fields[apps]" => "bundleId",
      "limit" => "2"
    )
    apps = app_response.fetch("data")
    raise "App Store Connect app not found for bundle ID #{bundle_id}" if apps.empty?
    raise "Multiple App Store Connect apps found for bundle ID #{bundle_id}" if apps.length > 1

    builds = get_all(
      "/v1/builds",
      "filter[app]" => apps.first.fetch("id"),
      "filter[preReleaseVersion.platform]" => "IOS",
      "filter[preReleaseVersion.version]" => marketing_version,
      "fields[builds]" => "version",
      "limit" => "200"
    )
    builds.map { |build| build.fetch("attributes").fetch("version") }
  end

  private

  def get_all(path, query)
    response = get(path, query)
    resources = response.fetch("data")

    while (next_url = response.dig("links", "next"))
      response = request(URI(next_url))
      resources.concat(response.fetch("data"))
    end

    resources
  end

  def get(path, query)
    uri = URI.join(API_BASE_URL, path)
    uri.query = URI.encode_www_form(query)
    request(uri)
  end

  def request(uri)
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise "App Store Connect request failed with HTTP #{response.code}"
    end

    JSON.parse(response.body)
  end

  def token
    issued_at = Time.now.to_i
    header = { alg: "ES256", kid: @key_id, typ: "JWT" }
    payload = {
      iss: @issuer_id,
      iat: issued_at,
      exp: issued_at + 5 * 60,
      aud: "appstoreconnect-v1"
    }
    signing_input = [header, payload]
      .map { |part| base64url(JSON.generate(part)) }
      .join(".")
    signature = @private_key.sign(OpenSSL::Digest::SHA256.new, signing_input)

    "#{signing_input}.#{base64url(raw_ecdsa_signature(signature))}"
  end

  def raw_ecdsa_signature(der_signature)
    integers = OpenSSL::ASN1.decode(der_signature).value
    integers.map { |integer| integer.value.to_s(16).rjust(64, "0") }.join.then do |hex|
      [hex].pack("H*")
    end
  end

  def base64url(value)
    Base64.urlsafe_encode64(value, padding: false)
  end
end

if $PROGRAM_NAME == __FILE__
  required_environment = %w[
    APP_BUNDLE_ID
    APP_MARKETING_VERSION
    APP_STORE_CONNECT_ISSUER_ID
    APP_STORE_CONNECT_KEY_ID
    APP_STORE_CONNECT_PRIVATE_KEY_PATH
    BUILD_NUMBER_OFFSET
  ]
  missing = required_environment.select { |name| ENV[name].to_s.empty? }
  abort "Missing required environment variables: #{missing.join(', ')}" unless missing.empty?

  client = AppStoreConnectClient.new(
    issuer_id: ENV.fetch("APP_STORE_CONNECT_ISSUER_ID"),
    key_id: ENV.fetch("APP_STORE_CONNECT_KEY_ID"),
    private_key_path: ENV.fetch("APP_STORE_CONNECT_PRIVATE_KEY_PATH")
  )
  versions = client.build_versions(
    bundle_id: ENV.fetch("APP_BUNDLE_ID"),
    marketing_version: ENV.fetch("APP_MARKETING_VERSION")
  )
  puts TestFlightBuildNumber.next_number(
    versions,
    offset: Integer(ENV.fetch("BUILD_NUMBER_OFFSET"), 10)
  )
end
