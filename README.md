# ChatServer: Fault-Tolerant Real-Time Chat in Elixir & Phoenix
=============================================================

**ChatServer** is a concurrent, fault-tolerant real-time chat backend built with **Elixir**,  **OTP**, and **Phoenix Channels**. Created as a hands-on mastery project, it demonstrates how to design isolated, self-healing backend processes and connect them to live WebSocket clients without race conditions or shared-memory headaches.

Whether you are a beginner learning how OTP processes work together or a developer looking to see how Phoenix Channels bridge backend state to real-time clients, this README breaks down the architecture, code examples, real-world use cases, and testing workflows in plain terms.

## Table of Contents
-----------------

1.  [What This Project Does](#what-this-project-does
)

2.  [How the System Fits Together](#how-the-system-fits-together)

3.  [Core Concepts, Code Examples & Real-World Uses](#core-concepts-code-examples--real-world-uses)

    -   [GenServer: Isolated State & Concurrency](#1-genserver-isolated-state--concurrency)

    -   [DynamicSupervisor: On-Demand Process Lifecycles](#2-dynamicsupervisor-on-demand-process-lifecycles)

    -   [Registry: Friendly Names to Process IDs](#3-registry-friendly-names-to-process-ids)

    -   [Phoenix Channels & PubSub: Live WebSockets & Event Fan-Out](#4-phoenix-channels--pubsub-live-websockets--event-fan-out)

4.  [Project Structure](#project-structure)

5.  [Hands-On Examples & Usage](#hands-on-examples--usage)

6.  [Testing Strategy (Unit & Channel Integration Tests)](#testing-strategy-unit--channel-integration-tests)

7.  [Key Lessons & Practical Tips](#key-lessons--practical-tips)

# What This Project Does
----------------------

In simple terms,  **ChatServer** powers chat rooms where users can:

-   **Join any room dynamically:** Joining `"room:lobby"` or `"room:gaming"` automatically spins up a dedicated room process if one does not already exist.

-   **Send and receive messages in real time:** Messages pushed over a WebSocket connection are broadcast to everyone subscribed to that room.

-   **Share typing indicators:** Clients can broadcast when they start or stop typing without echoing unnecessary noise back to themselves.

-   **Clean up automatically on disconnect:** When a client drops a connection,  `RoomChannel.terminate/2` triggers `ChatRoom.leave/2`, removing that socket from the room roster and notifying remaining members.

## How the System Fits Together

----------------------------

Instead of storing all chat rooms inside one giant dictionary or database table in memory, ChatServer gives **each room its own lightweight Elixir process**:

Plaintext

```
Client (WebSocket)
       │
       ▼
  UserSocket ──► RoomChannel (Phoenix WebSocket layer)
                     │
       ┌─────────────┴─────────────┐
       ▼                           ▼
 ChatRoom.join/3           Phoenix.PubSub
 ChatRoom.leave/2          ("room:<name>")
       │                           │
       ▼                           ▼
 RoomRegistry ──► ChatRoom (GenServer per room)
 (name -> PID)     started under RoomSupervisor (DynamicSupervisor)

```

When a user joins `"room:lobby"`:

1.  `RoomChannel` extracts the username and socket ID and calls `ChatServer.ChatRoom.join/3`.

2.  `ChatRoom` checks `RoomRegistry` for `"lobby"`.

3.  If the room does not exist yet,  `RoomSupervisor` (`DynamicSupervisor`) starts a new `ChatRoom` process registered under `"lobby"`.

4.  `ChatRoom` adds the user to its state map, broadcasts `{:user_joined, username, users}` over `ChatServer.PubSub`, and returns the current user list.

5.  `RoomChannel` subscribes to `"room:lobby"` on `ChatServer.PubSub`, forwards PubSub events to the WebSocket client via `handle_info/2`, and cleans up the user when the socket terminates.

## Core Concepts, Code Examples & Real-World Uses
----------------------------------------------

### 1\. GenServer: Isolated State & Concurrency

-   **In simple terms:** A `GenServer` (Generic Server) is an Elixir process designed to hold state and process messages one at a time in its mailbox. Instead of two threads fighting over shared memory with locks, callers send messages and get replies safely.

-   **Where it is helpful:** Whenever an entity---like a chat room, game match, or active session---needs its own live state and sequential updates under concurrent traffic.

-   **Real-world application examples:**

    -   **Multiplayer games & lobbies:** Each match or party can run as a process tracking player status, scores, or turn state independently.

    -   **Live checkout or cart sessions:** High-concurrency carts or seat-reservation holds can serialize conflicting updates cleanly.

**How it looks in `ChatRoom` (`lib/chat_server/chat_room.ex`):**

Elixir

```
defstruct [:room_name, users: %{}]

@impl true
def handle_call({:join, username, socket_id}, _from, state) do
  new_users = Map.put(state.users, socket_id, username)
  new_state = %{state | users: new_users}

  Phoenix.PubSub.broadcast(
    ChatServer.PubSub,
    "room:#{state.room_name}",
    {:user_joined, username, Map.values(new_users)}
  )

  {:reply, {:ok, Map.values(new_users)}, new_state}
end

```

### 2\. DynamicSupervisor: On-Demand Process Lifecycles

-   **In simple terms:** A standard `Supervisor` starts a fixed list of children when the app boots. A `DynamicSupervisor` starts and stops child processes **on demand** while the app is running.

-   **Where it is helpful:** When you do not know ahead of time how many rooms, workers, or streams will exist, and you want isolated lifecycles (`restart: :temporary` means a room process is not automatically revived after a normal exit).

-   **Real-world application examples:**

    -   **Video or voice call rooms:** Spin up a room or media-control process only when someone starts a call, and let it exit when everyone leaves.

    -   **On-demand background jobs:** Launch an isolated worker per export, transcode, or report so one bad input cannot take down the rest of the system.

**How it looks in `ChatRoom`:**

Elixir

```
use GenServer, restart: :temporary

defp start_room_and_join(room_name, username, socket_id) do
  DynamicSupervisor.start_child(ChatServer.RoomSupervisor, {__MODULE__, room_name})
  join(room_name, username, socket_id)
end

```

### 3\. Registry: Friendly Names to Process IDs

-   **In simple terms:** Processes in Elixir have PIDs like `#PID<0.312.0>`, which are dynamic and not human-friendly. A `Registry` lets you look up a process by a meaningful key---like `"lobby"`---and register processes using `{:via, Registry, ...}` tuples.

-   **Where it is helpful:** Whenever multiple components need to find or message a dynamic process by name without hardcoding PIDs or maintaining fragile manual lookup tables.

-   **Real-world application examples:**

    -   **IoT & connected devices:** Map a `device_id` (such as a smart meter or sensor) directly to the process managing its live telemetry stream.

    -   **Per-user connection hubs:** Route notifications or direct messages to a specific user's active session process.

**How it looks in `RoomRegistry` (`lib/chat_server/room_registry.ex`):**

Elixir

```
def via_tuple(room_name) do
  {:via, Registry, {ChatServer.RoomRegistry, room_name}}
end

def lookup(room_name) do
  case Registry.lookup(ChatServer.RoomRegistry, room_name) do
    [{pid, _}] -> {:ok, pid}
    [] -> {:error, :room_not_found}
  end
end

```

### 4\. Phoenix Channels & PubSub: Live WebSockets & Event Fan-Out

-   **In simple terms:** HTTP is normally request-response---the client asks, the server answers, and the exchange ends.  **Phoenix Channels** keep a persistent real-time connection open over WebSockets, while **PubSub** (Publish/Subscribe) lets publishers send events to a topic (like `"room:lobby"`) so every subscriber receives them.

-   **Where it is helpful:** Any feature where users expect instant updates without refreshing the page---chat, live feeds, notifications, or presence indicators.

-   **Real-world application examples:**

    -   **Collaborative tools & live boards:** Push cursor movement, status updates, or edits to everyone viewing the same workspace.

    -   **Live order, delivery, or market trackers:** Stream real-time status changes or price ticks to active subscribers.

**How it looks in `RoomChannel` (`lib/chat_server_web/channels/room_channel.ex`):**

Elixir

```
@impl true
def join("room:" <> room_name, payload, socket) do
  username = Map.get(payload, "username", "Anonymous")
  socket_id = socket.id || inspect(socket.channel_pid)

  case ChatServer.ChatRoom.join(room_name, username, socket_id) do
    {:ok, user_list} ->
      Phoenix.PubSub.subscribe(ChatServer.PubSub, "room:#{room_name}")

      socket =
        socket
        |> assign(:room_name, room_name)
        |> assign(:username, username)
        |> assign(:socket_id, socket_id)

      {:ok, %{status: "joined", users: user_list}, socket}

    {:error, reason} ->
      {:error, %{reason: reason}}
  end
end

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

```

Project Structure
-----------------

Plaintext

```
chat_server/
├── lib/
│   ├── chat_server/
│   │   ├── application.ex              # Starts PubSub, Registry, DynamicSupervisor, Endpoint
│   │   ├── chat_room.ex                # GenServer managing room roster & PubSub broadcasts
│   │   └── room_registry.ex            # Registry wrapper & via-tuple helper
│   └── chat_server_web/
│       ├── channels/
│       │   ├── room_channel.ex         # Join, message/typing handlers, PubSub bridge, terminate
│       │   └── user_socket.ex          # WebSocket entry point routing "room:*" to RoomChannel
│       └── endpoint.ex                 # Phoenix HTTP & WebSocket endpoint
└── test/
    ├── support/
    │   └── channel_case.ex             # ExUnit.CaseTemplate setting up Phoenix.ChannelTest
    ├── chat_server/
    │   └── chat_room_test.exs          # Unit tests for ChatRoom GenServer lifecycle
    └── chat_server_web/
        └── channels/
            └── room_channel_test.exs # Integration tests for RoomChannel & PubSub pushes

```

Hands-On Examples & Usage
-------------------------

### 1\. Try the Backend in `iex`

Start an interactive session with your project loaded:

Bash

```
iex -S mix

```

Run commands to spawn a room, add users, and test departures:

Elixir

```
# First user joins -> dynamically starts "lobby" and returns current roster
ChatServer.ChatRoom.join("lobby", "Alice", "sock_1")
# => {:ok, ["Alice"]}

# Second user joins -> returns full roster in the room
ChatServer.ChatRoom.join("lobby", "Bob", "sock_2")
# => {:ok, ["Alice", "Bob"]}

# Alice leaves -> removes "sock_1" and returns remaining users
ChatServer.ChatRoom.leave("lobby", "sock_1")
# => {:ok, ["Bob"]}

```

### 2\. Channel Events Supported by `RoomChannel`

| **Direction** | **Event / Message** | **Payload Shape** | **Purpose** |
| --- | --- | --- | --- |
| **Client → Server** | `phx_join` on `"room:<name>"` | `%{"username" => "Alice"}` | Joins the room (defaults to `"Anonymous"`) and returns `%{status: "joined", users: [...]}`. |
| **Client → Server** | `"new_message"` | `%{"body" => "Hi!"}` | Broadcasts `"message_received"` with `username`, `body`, and `timestamp`. |
| **Client → Server** | `"typing"` | `%{"is_typing" => true}` | Broadcasts `"user_typing"` to other subscribers (`broadcast_from!`). |
| **Server → Client** | `"user_joined"` | `%{username: "Bob", users: [...]}` | Pushed when a user joins via PubSub `{:user_joined, username, users}`. |
| **Server → Client** | `"user_left"` | `%{username: "Alice", users: [...]}` | Pushed when a user disconnects/leaves via PubSub `{:user_left, username, users}`. |

Testing Strategy (Unit & Channel Integration Tests)
---------------------------------------------------

Run the full test suite from the project root:

Bash

```
mix test

```

-   **Unit tests (`test/chat_server/chat_room_test.exs`):** Test `ChatRoom` directly using `ExUnit.Case, async: true`---verifying dynamic room creation,  `RoomRegistry` lookup, full-roster return values on join, and user removal on leave.

-   **Channel integration tests (`test/chat_server_web/channels/room_channel_test.exs`):** Use `ChatServerWeb.ChannelCase` (`test/support/channel_case.ex`) with `connect/2`,  `subscribe_and_join/4`,  `push/3`, and `assert_push/2` to verify end-to-end channel joins, message broadcasts, and multi-client `"user_joined"` notifications.

Key Lessons & Practical Tips
----------------------------

-   **Use unique room names in `async: true` tests:** If parallel tests all join `"room:lobby"`, they share the same room process and can see users from other tests (`["Alice", "Bob", "Alice"]`). Generating unique room names per test keeps tests isolated and reliable.

-   **Match payloads and event names explicitly:** Keep GenServer broadcast tuples (`{:user_joined, username, users}` and `{:user_left, username, users}`) aligned with `RoomChannel.handle_info/2` and client event names (`"message_received"`,  `"user_joined"`,  `"user_left"`).

-   **Always clean up on disconnect:** Assigning `:socket_id` in `join/3` and calling `ChatServer.ChatRoom.leave/2` in `terminate/2` prevents stale users from lingering in the room roster after a connection drops.