defmodule DarkorbitWeb.GameAuth do
  @moduledoc "Browser-session and signed game-socket authentication."

  import Phoenix.Controller
  import Plug.Conn

  alias Darkorbit.Accounts
  alias Darkorbit.Accounts.PlayerAccount

  @socket_salt "game socket"
  @socket_max_age 900

  def init(action), do: action

  def call(conn, :fetch_current_player), do: fetch_current_player(conn)

  def call(conn, :require_authenticated_player) do
    if conn.assigns[:current_player] do
      conn
    else
      conn
      |> put_flash(:error, "Sign in to launch your ship.")
      |> redirect(to: "/login")
      |> halt()
    end
  end

  def fetch_current_player(conn) do
    player_id = get_session(conn, :player_id)
    session_id = get_session(conn, :account_session_id)

    account =
      case session_id do
        session_id when is_binary(session_id) -> Accounts.get_by_session_id(session_id)
        _other -> nil
      end

    if match?(%PlayerAccount{id: ^player_id}, account) do
      assign(conn, :current_player, account)
    else
      conn
      |> delete_session(:player_id)
      |> delete_session(:account_session_id)
      |> assign(:current_player, nil)
    end
  end

  def log_in_player(conn, %PlayerAccount{} = account) do
    conn
    |> configure_session(renew: true)
    |> put_session(:player_id, account.id)
    |> put_session(:account_session_id, account.session_id)
  end

  def log_out_player(conn) do
    if account = conn.assigns[:current_player] do
      _result = Accounts.logout_account(account.id, account.session_id)
    end

    configure_session(conn, drop: true)
  end

  def socket_token(%PlayerAccount{} = account) do
    Phoenix.Token.sign(DarkorbitWeb.Endpoint, @socket_salt, %{
      player_id: account.id,
      session_id: account.session_id
    })
  end

  def verify_socket_token(token) when is_binary(token) do
    with {:ok, %{player_id: player_id, session_id: session_id}} <-
           Phoenix.Token.verify(DarkorbitWeb.Endpoint, @socket_salt, token,
             max_age: @socket_max_age
           ),
         %PlayerAccount{id: ^player_id, verification: %{"verified" => true}} = account <-
           Accounts.get_by_session_id(session_id) do
      {:ok, account}
    else
      _error -> :error
    end
  end

  def verify_socket_token(_token), do: :error
end
