defmodule DarkorbitWeb.HelmetController do
  use DarkorbitWeb, :controller

  alias Darkorbit.Helmets
  alias DarkorbitWeb.HelmetManager

  @doc """
  Redeem a QR invitation before connecting the viewer WebSocket. The phone
  persists this long-lived credential before joining the display channel,
  preventing any channel crash from consuming the invitation without saving
  the registration. Only a random one-use pairing invitation is accepted.
  """
  def pair(conn, %{"code" => code} = params) when is_binary(code) do
    name = Map.get(params, "device_name", "Phone headset")
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")

    case HelmetManager.redeem(code, name) do
      {:ok, %{credential: credential}} ->
        json(conn, %{credential: credential})
      {:error, :invalid_pairing} ->
        conn |> put_status(:gone) |> json(%{error: "invalid_pairing"})
      {:error, :already_paired} ->
        conn |> put_status(:conflict) |> json(%{error: "already_paired"})
      {:error, _reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "pairing_failed"})
    end
  end

  def pair(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(:unprocessable_entity)
    |> json(%{error: "invalid_pairing"})
  end


  @doc "Verify an existing read-only HMD credential (never accept bearer tokens in URLs)."
  def verify(conn, _params) do
    credential =
      conn
      |> get_req_header("authorization")
      |> List.first()
      |> case do
        "Bearer " <> value -> value
        _ -> nil
      end

    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")

    case Helmets.authenticate(credential) do
      {:ok, _device} -> json(conn, %{valid: true})
      :error -> conn |> put_status(:unauthorized) |> json(%{valid: false})
    end
  end

  def show(conn, params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> render(:show,
      page_title: "Pilot Helmet",
      pairing_code: Map.get(params, "pair", "")
    )
  end
end
