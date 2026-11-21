defmodule ChatServerWeb.UserSocket do
  use Phoenix.Socket

  # Channel routing map - mathces any topic starting with "room:" to the RoomChannel module
  channel "room:*", ChatServerWeb.RoomChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
