defmodule ChatServer.ChatRoomTest do
  use ExUnit.Case, async: true

  alias ChatServer.ChatRoom

  # Helper to generate unique room names for isolated test runs
  defp unique_room_name do
    "room_#{System.unique_integer([:positive])}"
  end

  test "joining a non-existent room spawns it dynamically and adds the user" do
    room = unique_room_name()

    assert {:ok, ["Alice"]} = ChatRoom.join(room, "Alice", "socket_1")

    # Verify the room process is registered
    assert {:ok, pid} = ChatServer.RoomRegistry.lookup(room)
    assert Process.alive?(pid)
  end

  test "multiple users can join the same room and track roster state" do
    room = unique_room_name()

    {:ok, ["Alice"]} = ChatRoom.join(room, "Alice", "socket_1")
    {:ok, users} = ChatRoom.join(room, "Bob", "socket_2")

    # Order depends on map insertion, but both should be present
    assert Enum.sort(users) ==["Alice", "Bob"]
  end

  test "a user leaving the room updates the roster and broadcast cleanup" do
    room = unique_room_name()

    {:ok, _} = ChatRoom.join(room, "Alice", "socket_1")
    {:ok, users} = ChatRoom.join(room, "Bob", "socket_2")
    assert Enum.sort(users) == ["Alice", "Bob"]

    # Stimulate Alice leaving via disconnect
    {:ok, remaining_users} = ChatRoom.leave(room, "socket_1")

    assert remaining_users == ["Bob"]
  end
end
