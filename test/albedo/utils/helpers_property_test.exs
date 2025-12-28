defmodule Albedo.Utils.HelpersPropertyTest do
  use ExUnit.Case, async: true
  use PropCheck

  alias Albedo.Utils.Helpers

  describe "compact/1 properties" do
    property "removes all nil values" do
      forall list <- list(oneof([integer(), atom(), binary(), nil])) do
        result = Helpers.compact(list)
        nil not in result
      end
    end

    property "preserves non-nil values in order" do
      forall list <- list(oneof([integer(), atom(), binary(), nil])) do
        result = Helpers.compact(list)
        expected = Enum.reject(list, &is_nil/1)
        result == expected
      end
    end

    property "result length <= input length" do
      forall list <- list(oneof([integer(), nil])) do
        result = Helpers.compact(list)
        length(result) <= length(list)
      end
    end

    property "idempotent - compacting twice equals compacting once" do
      forall list <- list(oneof([integer(), nil])) do
        once = Helpers.compact(list)
        twice = Helpers.compact(once)
        once == twice
      end
    end

    property "empty list returns empty list" do
      Helpers.compact([]) == []
    end

    property "list without nils is unchanged" do
      forall list <- list(integer()) do
        Helpers.compact(list) == list
      end
    end
  end

  describe "default_value/2 properties" do
    property "returns default when value is nil" do
      forall default <- term() do
        Helpers.default_value(nil, default) == default
      end
    end

    property "returns value when not nil" do
      forall {value, default} <- {non_nil_term(), term()} do
        Helpers.default_value(value, default) == value
      end
    end

    property "never returns nil when default is not nil" do
      forall {value, default} <- {oneof([nil, integer()]), integer()} do
        result = Helpers.default_value(value, default)
        result != nil
      end
    end
  end

  describe "default_list/1 properties" do
    property "returns empty list for nil" do
      Helpers.default_list(nil) == []
    end

    property "returns the list unchanged when given a list" do
      forall list <- list(term()) do
        Helpers.default_list(list) == list
      end
    end

    property "result is always a list" do
      forall input <- oneof([nil, list(integer())]) do
        is_list(Helpers.default_list(input))
      end
    end
  end

  defp non_nil_term do
    such_that(t <- term(), when: t != nil)
  end

  describe "safe_path?/1 properties" do
    property "rejects paths with .." do
      forall path <- path_with_traversal() do
        not Helpers.safe_path?(path)
      end
    end

    property "rejects absolute paths starting with /" do
      forall path <- absolute_path() do
        not Helpers.safe_path?(path)
      end
    end

    property "rejects paths starting with ~" do
      forall path <- home_path() do
        not Helpers.safe_path?(path)
      end
    end

    property "accepts safe relative paths" do
      forall path <- safe_relative_path() do
        Helpers.safe_path?(path)
      end
    end
  end

  describe "safe_path_component?/1 properties" do
    property "rejects . and .." do
      not Helpers.safe_path_component?(".") and
        not Helpers.safe_path_component?("..")
    end

    property "rejects components with slashes" do
      forall component <- component_with_slash() do
        not Helpers.safe_path_component?(component)
      end
    end

    property "rejects empty strings" do
      not Helpers.safe_path_component?("")
    end

    property "accepts valid directory names" do
      forall component <- valid_component() do
        Helpers.safe_path_component?(component)
      end
    end
  end

  defp path_with_traversal do
    oneof([
      let(prefix <- binary(), do: prefix <> "../" <> "file"),
      let(suffix <- binary(), do: "../" <> suffix),
      let(middle <- binary(), do: "path/" <> middle <> "/../other")
    ])
  end

  defp absolute_path do
    let(path <- non_empty(binary()), do: "/" <> path)
  end

  defp home_path do
    let(path <- non_empty(binary()), do: "~/" <> path)
  end

  defp safe_relative_path do
    let(
      parts <- non_empty(list(valid_component())),
      do: Enum.join(parts, "-")
    )
  end

  defp component_with_slash do
    let(
      {before, after_slash} <- {non_empty(utf8()), non_empty(utf8())},
      do: before <> "/" <> after_slash
    )
  end

  defp valid_component do
    such_that(
      c <- non_empty(utf8()),
      when:
        c != "." and c != ".." and
          not String.contains?(c, ["/", "\\", "\0", ".."]) and
          not String.starts_with?(c, "~")
    )
  end
end
