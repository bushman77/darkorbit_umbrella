defmodule DarkorbitWeb.PageControllerTest do
  use DarkorbitWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ ~s(id="landing-page")
    assert html_response(conn, 200) =~ ~s(id="launch-client-link")
  end
end
