defmodule DarkorbitWeb.UserSocket do
  use Phoenix.Socket

  alias DarkorbitWeb.GameAuth

  channel "world:*", DarkorbitWeb.WorldChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case GameAuth.verify_socket_token(token) do
      {:ok, account} ->
        {:ok,
         socket
         |> assign(:current_player_id, account.id)
         |> assign(:current_pilot_name, account.pilot_name)}

      :error ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "player_socket:#{socket.assigns.current_player_id}"
end
