defmodule ChatServer.RoomRegistry do
  @moduledoc """
  Provides process registration for dynamic chat rooms using Elixir's Registry.
  """

  @doc """
  Generates a tuple used to address a process via the Registry dynamically.
  """
  def via_tuple(room_name) do
    {:via, Registry, {__MODULE__, room_name}}
  end

  @doc """
  Looks up a room process PID by its room name.
  Returns {:ok, pid} if found, or {:error, :room_not_found} if it doesn't exist.
  """
  def lookup(room_name) do
    case Registry.lookup(__MODULE__, room_name) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :room_not_found}
    end
  end
end
