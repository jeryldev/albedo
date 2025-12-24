defmodule AlbedoTest do
  use ExUnit.Case, async: true

  describe "version/0" do
    test "returns version string" do
      version = Albedo.version()
      assert is_binary(version)
      assert version == "0.1.0"
    end
  end

  describe "configured?/0" do
    test "returns false when no API key configured" do
      refute Albedo.configured?()
    end
  end
end
