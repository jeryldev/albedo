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
end
