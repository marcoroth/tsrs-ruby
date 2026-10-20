# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Tsrs
  class PackagingTest < Minitest::Spec
    def root
      File.expand_path("../..", __dir__)
    end

    def extension
      Dir[File.join(root, "lib", "tsrs", "tsrs.{bundle,so}")].first
    end

    def loads_from(lib)
      ruby = File.join(RbConfig::CONFIG["bindir"], RbConfig::CONFIG["ruby_install_name"])
      script = %(require "tsrs"; print Tsrs.tsrs_version)
      env = { "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil, "BUNDLER_SETUP" => nil }

      IO.popen(env, [ruby, "-I#{lib}", "-e", script], err: [:child, :out], &:read)
    end

    def layout(dir, into)
      lib = File.join(dir, "lib")

      FileUtils.mkdir_p(File.join(lib, "tsrs"))
      FileUtils.cp(File.join(root, "lib", "tsrs.rb"), lib)
      FileUtils.cp(Dir[File.join(root, "lib", "tsrs", "*.rb")], File.join(lib, "tsrs"))

      if into
        FileUtils.mkdir_p(File.join(lib, "tsrs", into))
        FileUtils.cp(extension, File.join(lib, "tsrs", into))
      end

      lib
    end

    test "loads the extension a platform gem ships, under the Ruby it was built for" do
      Dir.mktmpdir do |dir|
        abi = RUBY_VERSION.split(".").first(2).join(".")

        assert_equal Tsrs.tsrs_version, loads_from(layout(dir, abi))
      end
    end

    test "loads the extension a source install leaves beside the library" do
      Dir.mktmpdir do |dir|
        assert_equal Tsrs.tsrs_version, loads_from(layout(dir, "."))
      end
    end

    test "says so loudly when there is no extension at all" do
      Dir.mktmpdir do |dir|
        assert_equal true, loads_from(layout(dir, nil)).include?("LoadError")
      end
    end
  end
end
