defmodule ChatServerWeb.RoomChannelTest do
  use ChatServerWeb.ChannelCase

  alias ChatServerWeb.{UserSocket, RoomChannel}

  setup do
    # Connect an unauthenticated socket for testing
    {:ok, socket} = connect(UserSocket, %{})
    {:ok, socket: socket}
  end
  # Helper to generate unique room topics for test isolation
  defp unique_room_topic do
    "room:room_#{System.unique_integer([:positive])}"
  end

  test "successful join to room channel adds user and returns roster", %{socket: socket} do
    room_topic = unique_room_topic()

    # Stimulate a client connecting and joining the channel
    assert {:ok, %{users: users}, socket} =
      subscribe_and_join(socket, RoomChannel, room_topic, %{"username" => "Alice"})

      assert users == ["Alice"]
      assert socket.assigns.username == "Alice"
  end

  test "broadcasting new_message shouts to all channel subscribers", %{socket: socket} do
    room_topic = unique_room_topic()

    {:ok, _, socket} =
      subscribe_and_join(socket, RoomChannel, room_topic, %{"username" => "Alice"})

      # Push a message through the websocket into the channel
      push(socket, "new_message", %{"body" => "Hello everyone!"})

      # Assert that a "shout" broadcast is sent out to subscribers
      assert_broadcast "message_received", %{username: "Alice", body: "Hello everyone!"}
  end

  test "joining notifies existing room members via PubSub broadcast", %{socket: socket} do
    room_topic = unique_room_topic()

    # Alice joins first
    {:ok, _, alice_socket} =
      subscribe_and_join(socket, RoomChannel, room_topic, %{"username" => "Alice"})

      # Connect a second socket for Bob
      {:ok, bob_socket} = connect(UserSocket, %{})

      # Bob joins the same room
      {:ok, _, _} =
        subscribe_and_join(bob_socket, RoomChannel, room_topic, %{"username" => "Bob"})

        # Assert that Alice's socket receives the user_joined broadcast
        assert_push "user_joined", %{username: "Bob", users: users}
        assert Enum.sort(users) == ["Alice", "Bob"]
  end
end
