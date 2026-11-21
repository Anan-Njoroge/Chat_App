defmodule ChatServer.ChatRoom do
  @moduledoc """
  Manages the state and user list for an individual chat room using GenServer.

  use GenServer, restart: :dynamic: Injects boilerplate GenServer code into this module. restart: :dynamic tells the supervisor that rooms can be created and destroyed dynamically on the fly.

  defstruct [:room_name, users: %{}]: Defines the structural blueprint for this room's internal memory state. It holds the room_name (string) and a map of users currently inside it.


  """

  use GenServer, restart: :temporary

  defstruct [:room_name, users: %{}]

  # --- Client API ---
  @doc """
  Starts a new chat room process linked to the Registry.

  def start_link(room_name) do: The function invoked when spawning a new room process.

  GenServer.start_link(...): Boots up a new background process running this module's code, initializes it with room_name, and registers its name using our via_tuple helper so it can be addressed globally.

"""
  def start_link(room_name) do
    GenServer.start_link(__MODULE__, room_name, name: ChatServer.RoomRegistry.via_tuple(room_name))
  end

  @doc """
  Allows a user to join a room. If the room doesn't exist yet, it spawns it dynamically.

  def join(room_name, username, socket_id) do: The public function called when a user wants to enter a room.

  case ChatServer.RoomRegistry.lookup(room_name) do: It checks if the room process is already alive:

    If found ({:ok, pid}): It sends a synchronous synchronous message (GenServer.call) to that specific room process saying: "Hey, add this user."

    If not found ({:error, :room_not_found}): It triggers start_room_and_join/3.
  """
  #   Allows a user to join a room. If the room doesn't exist yet, it spawns it dynamically  and handles race conditions gracefully.

  def join(room_name, username, socket_id) do
    case ChatServer.RoomRegistry.lookup(room_name) do
      {:ok, pid} ->
        GenServer.call(pid, {:join, username, socket_id})

      {:error, :room_not_found} ->
        case DynamicSupervisor.start_child(ChatServer.RoomSupervisor, {__MODULE__, room_name}) do
          {:ok, pid} ->
            GenServer.call(pid, {:join, username, socket_id})

          {:error, {:already_started, pid}} ->
            GenServer.call(pid, {:join, username, socket_id})

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Removes a user frm the room when they disconnect or leave. It removes the user from the internal state and broadcasts a leave event to all subscribers in the room.
  """
  def leave(room_name, socket_id) do
    case ChatServer.RoomRegistry.lookup(room_name) do
      {:ok, pid} -> GenServer.call(pid, {:leave, socket_id})
      {:error, :room_not_found} -> :ok
    end
  end

  # -- GenServer Callbacks ---
  @doc """
  Initializes the GenServer state with an empty user map for the given room.

  @impl true: A compiler check ensuring we are correctly implementing a required GenServer callback behavior.

  def init(room_name) do: Runs the exact second the room process is born. It returns {:ok, initial_state}, setting up an empty map of users (users: %{}).
  """
  @impl true
  def init(room_name) do
    {:ok, %__MODULE__{room_name: room_name, users: %{}}}
  end

  @doc """
  Handles synchronous join requests, updates the user map, and broadcasts the join event via PubSub.

  def handle_call({:join, username, socket_id}, _from, state) do: This function receives messages sent via GenServer.call. It unpacks the user's details and accesses the current process state.

  Map.put(...): Adds the new user into the room's memory map using their unique socket identifier as the key.

  Phoenix.PubSub.broadcast(...): Instantly shouts a notification across the server's central switchboard (ChatServer.PubSub) to the topic "room:name", letting everyone else inside that room know someone joined.

  {:reply, {:ok, Map.values(new_users)}, new_state}: Sends the updated list of users back to the user who requested to join, and saves the new_state into the process memory for next time.
  """
  @impl true
  def handle_call({:join, username, socket_id}, _from, state) do
    new_users = Map.put(state.users, socket_id, username)
    new_state = %{state | users: new_users}

    # Broadcast to phoenix PubSub so all subscribers in the room get notified of the new user
    Phoenix.PubSub.broadcast(
      ChatServer.PubSub,
      "room:#{state.room_name}",
      {:user_joined, username, Map.values(new_users)}
    )

    {:reply, {:ok, Map.values(new_users)}, new_state}
  end

  @impl true
  def handle_call({:leave, socket_id}, _from, state) do
    {username, new_users} = Map.pop(state.users, socket_id)
    new_state = %{state | users: new_users}

    if username do
      Phoenix.PubSub.broadcast(
        ChatServer.PubSub,
        "room:#{state.room_name}",
        {:user_left, username, Map.values(new_users)}
      )
    end

    {:reply, {:ok, Map.values(new_users)}, new_state}
  end
end
