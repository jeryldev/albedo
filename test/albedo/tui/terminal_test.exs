defmodule Albedo.TUI.TerminalTest do
  use ExUnit.Case, async: true

  alias Albedo.TUI.Terminal

  describe "ANSI escape code functions" do
    test "hide_cursor returns proper escape sequence" do
      import ExUnit.CaptureIO

      output = capture_io(fn -> Terminal.hide_cursor() end)
      assert output == "\e[?25l"
    end

    test "show_cursor returns proper escape sequence" do
      import ExUnit.CaptureIO

      output = capture_io(fn -> Terminal.show_cursor() end)
      assert output == "\e[?25h"
    end

    test "enter_alternate_screen returns proper escape sequence" do
      import ExUnit.CaptureIO

      output = capture_io(fn -> Terminal.enter_alternate_screen() end)
      assert output == "\e[?1049h"
    end

    test "exit_alternate_screen returns proper escape sequence" do
      import ExUnit.CaptureIO

      output = capture_io(fn -> Terminal.exit_alternate_screen() end)
      assert output == "\e[?1049l"
    end
  end

  describe "restore_mode/1" do
    test "returns :ok for non-binary input" do
      assert Terminal.restore_mode(nil) == :ok
      assert Terminal.restore_mode(:something) == :ok
    end
  end
end
