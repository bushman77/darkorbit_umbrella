defmodule DarkorbitWeb.UserSocket do
  use Phoenix.Socket

  alias DarkorbitWeb.GameAuth
  alias Darkorbit.Helmets

  channel "world:*", DarkorbitWeb.WorldChannel
  channel "helmet:*", DarkorbitWeb.HelmetChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case GameAuth.verify_socket_token(token) do
      {:ok, account} ->
        {:ok,
         socket
         |> assign(:socket_role, :pilot)
         |> assign(:current_player_id, account.id)
         |> assign(:current_pilot_name, account.pilot_name)}

      :error ->
        :error
    end
  end

  # QR invitations are redeemed via POST /helmet/pair, which lets the phone
  # persist its durable viewer credential BEFORE any WebSocket channel joins.
  # The WebSocket only accepts a registered helmet bearer token.

  def connect(%{"helmet_token" => credential}, socket, _connect_info) do
    case Helmets.authenticate(credential) do
      {:ok, device} ->
        {:ok, socket
         |> assign(:socket_role, :helmet)
         |> assign(:helmet_player_id, device.player_id)
         |> assign(:helmet_device_id, device.id)}
      :error -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(%{assigns: %{socket_role: :pilot, current_player_id: player_id}}),
    do: "player_socket:#{player_id}"
  def id(_socket), do: nil
end
