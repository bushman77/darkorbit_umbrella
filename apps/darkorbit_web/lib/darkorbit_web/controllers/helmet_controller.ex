defmodule DarkorbitWeb.HelmetController do
  use DarkorbitWeb, :controller

  alias Darkorbit.Helmets

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
