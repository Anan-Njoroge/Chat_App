defmodule ChatServerWeb.RoomChannel do
  @moduledoc """
  Handles WebSocket connections for chat rooms, allowing users to join, send messages,
  and receive updates in real time for specific chat topics using Phoenix channels.
  """
  use ChatServerWeb, :channel

  @doc """
  Authorizes and authenticates a client attempting to join a specific chat room topic.
  It checks the provided username and room name, and if valid, allows the user to join the channel.
  """
  @impl true
  def join("room:" <> room_name, payload, socket) do
    # Extract the username from the connection payload, defaulting to "Anonymous"
    username = Map.get(payload, "username", "Anonymous")
    socket_id = socket.id || inspect(socket.channel_pid)

    # Call our ChatRoom GenServer to join the process (spawning it dynamically if needed)
    case ChatServer.ChatRoom.join(room_name, username, socket_id) do
      {:ok, user_list} ->
        # Subscribe this channel process to the PubSub room topic for real-time broadcasts
        Phoenix.PubSub.subscribe(ChatServer.PubSub, "room:#{room_name}")

        # Assign room name, username, and socket_id to the socket's private session state
        socket =
          socket
          |> assign(:room_name, room_name)
          |> assign(:username, username)
          |> assign(:socket_id, socket_id)

        # Send back a success reply to the client containing the current user roster in the room
        {:ok, %{status: "joined", users: user_list}, socket}

      {:error, reason} ->
        # If joining fails, send back an error reply to the client with the reason.
        {:error, %{reason: reason}}
    end
  end

  @doc """
  Handles incoming messages ("new_message") and typing indicator events ("typing")
  from clients in the chat room, broadcasting updates in real time to subscribers.
  """
  @impl true
  def handle_in("new_message", %{"body" => body}, socket) do
    username = socket.assigns.username

    # Broadcast the new message to all subscribers of the room topic
    broadcast!(socket, "message_received", %{
      username: username,
      body: body,
      timestamp: DateTime.utc_now() |> DateTime.to_string()
    })

    {:noreply, socket}
  end

  @impl true
  def handle_in("typing", %{"is_typing" => is_typing}, socket) do
    username = socket.assigns.username

    # Broadcast typing status to all subscribers in the room
    broadcast_from!(socket, "user_typing", %{
      username: username,
      is_typing: is_typing
    })

    {:noreply, socket}
  end

  @doc """
  Handles incoming PubSub broadcasts from the backend GenServer and pushes them to the WebSocket client.
  """
  @impl true
  def handle_info({:user_joined, username, users}, socket) do
    push(socket, "user_joined", %{username: username, users: users})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:user_left, username, users}, socket) do
    push(socket, "user_left", %{username: username, users: users})
    {:noreply, socket}
  end

  @doc """
  Handles cleanup when a client drops the connection or leaves the channel.
  """
  @impl true
  def terminate(_reason, socket) do
    room_name = socket.assigns[:room_name]
    socket_id = socket.assigns[:socket_id]

    if room_name && socket_id do
      ChatServer.ChatRoom.leave(room_name, socket_id)
    end

    :ok
  end
end
