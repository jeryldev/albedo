defmodule Albedo.TUI.StateStatefulTest do
  @moduledoc """
  Stateful property-based tests for TUI.State using PropCheck.
  Tests state machine invariants under random operation sequences.
  """

  use ExUnit.Case, async: true
  use PropCheck

  alias Albedo.TUI.State

  @panels [:projects, :tickets, :research, :detail]

  describe "panel navigation properties" do
    property "next_panel cycles through all panels" do
      forall n <- choose(1, 20) do
        state = State.new()

        final_state =
          Enum.reduce(1..n, state, fn _, acc ->
            State.next_panel(acc)
          end)

        final_state.active_panel in @panels
      end
    end

    property "4 next_panel calls returns to original panel" do
      forall initial_panel <- oneof(@panels) do
        state = %{State.new() | active_panel: initial_panel}

        final_state =
          state
          |> State.next_panel()
          |> State.next_panel()
          |> State.next_panel()
          |> State.next_panel()

        final_state.active_panel == initial_panel
      end
    end

    property "prev_panel is inverse of next_panel" do
      forall initial_panel <- oneof(@panels) do
        state = %{State.new() | active_panel: initial_panel}

        result =
          state
          |> State.next_panel()
          |> State.prev_panel()

        result.active_panel == initial_panel
      end
    end
  end

  describe "mode transition properties" do
    property "enter then exit help mode returns to normal" do
      state =
        State.new()
        |> State.enter_help_mode()
        |> State.exit_help_mode()

      state.mode == :normal
    end

    property "enter then exit confirm mode returns to normal" do
      forall msg <- utf8() do
        state =
          State.new()
          |> State.enter_confirm_mode(:delete, msg)
          |> State.exit_confirm_mode()

        state.mode == :normal and state.confirm_action == nil
      end
    end

    property "enter then exit input mode returns to normal" do
      forall {mode, prompt} <- {atom(), utf8()} do
        state =
          State.new()
          |> State.enter_input_mode(mode, prompt)
          |> State.exit_input_mode()

        state.mode == :normal and state.input_mode == nil and state.input_buffer == nil
      end
    end
  end

  describe "input buffer properties" do
    property "input_insert_char grows buffer" do
      forall chars <- non_empty(list(printable_char())) do
        initial_state =
          State.new()
          |> State.enter_input_mode(:test, "test")

        final_state =
          Enum.reduce(chars, initial_state, fn char, acc ->
            State.input_insert_char(acc, char)
          end)

        String.length(final_state.input_buffer) == length(chars)
      end
    end

    property "input_delete_char shrinks buffer" do
      forall chars <- non_empty(list(printable_char())) do
        initial_state =
          State.new()
          |> State.enter_input_mode(:test, "test")

        with_chars =
          Enum.reduce(chars, initial_state, fn char, acc ->
            State.input_insert_char(acc, char)
          end)

        after_delete = State.input_delete_char(with_chars)

        String.length(after_delete.input_buffer) == length(chars) - 1
      end
    end

    property "cursor stays within buffer bounds" do
      forall ops <- list(oneof([:left, :right, {:insert, printable_char()}, :delete])) do
        initial_state =
          State.new()
          |> State.enter_input_mode(:test, "test")

        final_state =
          Enum.reduce(ops, initial_state, fn op, acc ->
            case op do
              :left -> State.input_move_cursor_left(acc)
              :right -> State.input_move_cursor_right(acc)
              {:insert, char} -> State.input_insert_char(acc, char)
              :delete -> State.input_delete_char(acc)
            end
          end)

        final_state.input_cursor >= 0 and
          final_state.input_cursor <= String.length(final_state.input_buffer)
      end
    end
  end

  describe "movement properties" do
    property "move_up never produces negative index" do
      forall n <- choose(1, 100) do
        state = State.new()

        final_state =
          Enum.reduce(1..n, state, fn _, acc ->
            State.move_up(acc)
          end)

        final_state.current_project >= 0 and
          (final_state.selected_ticket == nil or final_state.selected_ticket >= 0) and
          final_state.selected_file >= 0
      end
    end

    property "move_down never produces negative index" do
      forall n <- choose(1, 100) do
        state = State.new()

        final_state =
          Enum.reduce(1..n, state, fn _, acc ->
            State.move_down(acc)
          end)

        final_state.current_project >= 0
      end
    end
  end

  describe "quit property" do
    property "quit sets quit flag" do
      state = State.new() |> State.quit()
      state.quit == true
    end
  end

  describe "message property" do
    property "set_message stores message" do
      forall msg <- utf8() do
        state = State.new() |> State.set_message(msg)
        state.message == msg
      end
    end
  end

  defp printable_char do
    let c <- choose(32, 126) do
      <<c::utf8>>
    end
  end
end
