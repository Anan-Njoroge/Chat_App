defmodule ChatServerWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.

  Such tests rely on `Phoenix.ChannelTest` and also
  import other functionality to make it easier
  to test WebSocket endpoints and channels.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      import ChatServerWeb.ChannelCase

      # The default endpoint for testing
      @endpoint ChatServerWeb.Endpoint
    end
  end

  setup _tags do
    :ok
  end
end
