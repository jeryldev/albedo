Application.put_env(:albedo, :test_mode, true)

ExUnit.start(capture_log: true)
