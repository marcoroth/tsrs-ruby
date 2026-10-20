# frozen_string_literal: true

require "test_helper"

class TsrsTest < Minitest::Spec
  test "has a version number" do
    assert_equal "0.18.0", Tsrs::VERSION
  end

  test "the native library was built from the version the gem was" do
    assert_equal Tsrs::VERSION, Tsrs::Backend.version
  end

  test "reports the version of tsrs it was compiled against" do
    assert_equal "0.18.0", Tsrs.tsrs_version
  end

  test "the version it reports is the one Cargo.lock pins" do
    locked = File.read(File.expand_path("../rust/Cargo.lock", __dir__))[/name = "tsrs_api"\nversion = "([^"]+)"/, 1]

    assert_equal locked, Tsrs.tsrs_version
  end

  test "reports the TypeScript version tsrs release builds stamp" do
    assert_equal "7.1.0-dev.20260930.4", Tsrs.typescript_version
  end

  test "tsc reports the same TypeScript version" do
    assert_equal true, Tsrs.tsc("--version").output.start_with?("Version #{Tsrs.typescript_version} (tsrs #{Tsrs.tsrs_version}-")
  end
end
