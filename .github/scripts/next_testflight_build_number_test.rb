# frozen_string_literal: true

require "minitest/autorun"
require_relative "next_testflight_build_number"

class TestFlightBuildNumberTest < Minitest::Test
  def test_uses_offset_when_no_build_exists
    assert_equal "42", TestFlightBuildNumber.next_number([], offset: 42)
  end

  def test_advances_past_existing_integer_builds
    assert_equal "143", TestFlightBuildNumber.next_number(%w[1 100 42], offset: 43)
  end

  def test_advances_past_the_major_component_of_dotted_builds
    assert_equal "13", TestFlightBuildNumber.next_number(%w[9.99.99 10.2.3], offset: 3)
  end

  def test_rejects_invalid_existing_builds
    assert_raises(ArgumentError) do
      TestFlightBuildNumber.next_number(["1-beta"], offset: 1)
    end
  end

  def test_rejects_nonpositive_offsets
    assert_raises(ArgumentError) do
      TestFlightBuildNumber.next_number(["1"], offset: 0)
    end
  end

  def test_converts_ecdsa_signature_to_jwt_raw_format
    key = OpenSSL::PKey::EC.generate("prime256v1")
    signature = key.sign(OpenSSL::Digest::SHA256.new, "payload")
    client = AppStoreConnectClient.allocate

    assert_equal 64, client.send(:raw_ecdsa_signature, signature).bytesize
  end
end
