defmodule Albedo.Utils.BackoffTest do
  use ExUnit.Case, async: true

  alias Albedo.Utils.Backoff

  describe "calculate_delay/3" do
    test "returns value within expected range for attempt 0" do
      delays = for _ <- 1..100, do: Backoff.calculate_delay(0, 1000, 30_000)

      assert Enum.all?(delays, &(&1 >= 0 and &1 <= 1000))
    end

    test "returns value within expected range for attempt 1" do
      delays = for _ <- 1..100, do: Backoff.calculate_delay(1, 1000, 30_000)

      assert Enum.all?(delays, &(&1 >= 0 and &1 <= 2000))
    end

    test "returns value within expected range for attempt 3" do
      delays = for _ <- 1..100, do: Backoff.calculate_delay(3, 1000, 30_000)

      assert Enum.all?(delays, &(&1 >= 0 and &1 <= 8000))
    end

    test "respects max_delay cap" do
      delays = for _ <- 1..100, do: Backoff.calculate_delay(10, 1000, 5000)

      assert Enum.all?(delays, &(&1 >= 0 and &1 <= 5000))
    end

    test "produces varied delays due to jitter" do
      delays = for _ <- 1..50, do: Backoff.calculate_delay(2, 1000, 30_000)
      unique_delays = Enum.uniq(delays)

      assert length(unique_delays) > 1
    end
  end

  describe "with_retry/2" do
    test "returns success immediately on first attempt" do
      result = Backoff.with_retry(fn -> {:ok, "success"} end)

      assert result == {:ok, "success"}
    end

    test "returns error if not retryable" do
      result =
        Backoff.with_retry(
          fn -> {:error, :not_retryable} end,
          retry_on: fn _ -> false end
        )

      assert result == {:error, :not_retryable}
    end

    test "retries on retryable error and eventually succeeds" do
      counter = :counters.new(1, [:atomics])

      result =
        Backoff.with_retry(
          fn ->
            count = :counters.get(counter, 1)
            :counters.add(counter, 1, 1)

            if count < 2 do
              {:error, :temporary_failure}
            else
              {:ok, "success after retry"}
            end
          end,
          base_delay_ms: 1,
          max_retries: 3
        )

      assert result == {:ok, "success after retry"}
      assert :counters.get(counter, 1) == 3
    end

    test "respects max_retries limit" do
      counter = :counters.new(1, [:atomics])

      result =
        Backoff.with_retry(
          fn ->
            :counters.add(counter, 1, 1)
            {:error, :always_fails}
          end,
          base_delay_ms: 1,
          max_retries: 2
        )

      assert result == {:error, :always_fails}
      assert :counters.get(counter, 1) == 3
    end

    test "calls on_retry callback before each retry" do
      retry_log = Agent.start_link(fn -> [] end) |> elem(1)

      Backoff.with_retry(
        fn -> {:error, :fail} end,
        base_delay_ms: 1,
        max_retries: 2,
        on_retry: fn attempt, delay, reason ->
          Agent.update(retry_log, &[{attempt, delay, reason} | &1])
        end
      )

      log = Agent.get(retry_log, & &1) |> Enum.reverse()

      assert length(log) == 2
      assert [{1, _, :fail}, {2, _, :fail}] = log
    end

    test "retry_on function controls which errors are retried" do
      counter = :counters.new(1, [:atomics])

      Backoff.with_retry(
        fn ->
          count = :counters.get(counter, 1)
          :counters.add(counter, 1, 1)

          if count == 0, do: {:error, :retryable}, else: {:error, :not_retryable}
        end,
        base_delay_ms: 1,
        max_retries: 3,
        retry_on: fn
          {:error, :retryable} -> true
          _ -> false
        end
      )

      assert :counters.get(counter, 1) == 2
    end
  end

  describe "retryable_llm_error?/1" do
    test "returns true for timeout errors" do
      assert Backoff.retryable_llm_error?({:error, :timeout})
    end

    test "returns true for rate limited errors" do
      assert Backoff.retryable_llm_error?({:error, :rate_limited})
    end

    test "returns true for request failed errors" do
      assert Backoff.retryable_llm_error?({:error, {:request_failed, %{reason: :timeout}}})
      assert Backoff.retryable_llm_error?({:error, {:request_failed, :econnrefused}})
    end

    test "returns true for 5xx HTTP errors" do
      assert Backoff.retryable_llm_error?({:error, {:http_error, 500, "Server Error"}})
      assert Backoff.retryable_llm_error?({:error, {:http_error, 502}})
      assert Backoff.retryable_llm_error?({:error, {:http_error, 503, "Service Unavailable"}})
    end

    test "returns true for 429 rate limit HTTP errors" do
      assert Backoff.retryable_llm_error?({:error, {:http_error, 429, "Too Many Requests"}})
      assert Backoff.retryable_llm_error?({:error, {:http_error, 429}})
    end

    test "returns false for 4xx client errors (except 429)" do
      refute Backoff.retryable_llm_error?({:error, {:http_error, 400, "Bad Request"}})
      refute Backoff.retryable_llm_error?({:error, {:http_error, 401, "Unauthorized"}})
      refute Backoff.retryable_llm_error?({:error, {:http_error, 403, "Forbidden"}})
      refute Backoff.retryable_llm_error?({:error, {:http_error, 404, "Not Found"}})
    end

    test "returns false for unknown provider error" do
      refute Backoff.retryable_llm_error?({:error, {:unknown_provider, "invalid"}})
    end

    test "returns false for success tuples" do
      refute Backoff.retryable_llm_error?({:ok, "response"})
    end
  end
end
