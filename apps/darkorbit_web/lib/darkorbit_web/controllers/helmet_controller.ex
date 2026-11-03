defmodule DarkorbitWeb.HelmetController do
  use DarkorbitWeb, :controller

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
