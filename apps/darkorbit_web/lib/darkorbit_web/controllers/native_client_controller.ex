defmodule DarkorbitWeb.NativeClientController do
  @moduledoc """
  Stateless JSON bootstrap for the locally bundled desktop game client.
  The browser's Phoenix cookie session is not used or exposed.
  """
  use DarkorbitWeb, :controller

  alias Darkorbit.Accounts
  alias DarkorbitWeb.{GameAuth, NativeLoginLimiter}

  @token_lifetime_seconds 900

  # Credential-free diagnostic: exercises the same native CORS and JSON API
  # pipeline as login without consuming rate limits or transmitting secrets.
  def probe(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(%{status: "ok"})
  end

  def login(conn, %{"username" => username, "password" => password})
      when is_binary(username) and is_binary(password) do
    cond do
      byte_size(username) > 80 or byte_size(password) > 512 or
          String.trim(username) == "" or password == "" ->
        invalid_login(conn)

      not NativeLoginLimiter.allow?(username) ->
        conn
        |> put_resp_header("retry-after", "300")
        |> put_status(:too_many_requests)
        |> json(%{error: "Too many attempts. Try again in a few minutes."})

      true ->
        case Accounts.login_account(username, password) do
          {:ok, account} ->
            NativeLoginLimiter.clear(username)
            json(conn, credentials(account))

          {:error, _} ->
            invalid_login(conn)
        end
    end
  end

  def login(conn, _), do: invalid_login(conn)

  def refresh(conn, _params) do
    with {:ok, account} <- authenticate_bearer(conn) do
      json(conn, credentials(account))
    else
      _ -> unauthorized(conn)
    end
  end

  def logout(conn, _params) do
    with {:ok, account} <- authenticate_bearer(conn),
         {:ok, _} <- Accounts.logout_account(account.id, account.session_id) do
      send_resp(conn, :no_content, "")
    else
      _ -> unauthorized(conn)
    end
  end

  defp credentials(account) do
    %{
      token: GameAuth.socket_token(account),
      expires_in: @token_lifetime_seconds,
      pilot_id: account.id,
      pilot_name: account.pilot_name
    }
  end

  defp authenticate_bearer(conn) do
    token =
      get_req_header(conn, "authorization")
      |> Enum.find_value(fn
        "Bearer " <> value -> value
        _ -> nil
      end)

    GameAuth.verify_socket_token(token)
  end

  defp invalid_login(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Invalid or unverified pilot credentials."})
  end

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Pilot session expired. Sign in again."})
  end
end
