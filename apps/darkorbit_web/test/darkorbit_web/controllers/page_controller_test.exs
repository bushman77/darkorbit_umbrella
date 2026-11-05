defmodule DarkorbitWeb.PageControllerTest do
  use DarkorbitWeb.ConnCase

  test "GET / introduces Space Nova and exposes play and registration", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    document = LazyHTML.from_document(html)

    assert html =~ "SPACE NOVA"
    assert html =~ "An entire system."
    assert html =~ "Solar Atlas navigation"
    assert html =~ "Desktop client in development"

    assert Enum.count(LazyHTML.query(document, "#landing-page")) == 1
    assert Enum.count(LazyHTML.query(document, "#launch-client-link[href='/login']")) == 1
    assert Enum.count(LazyHTML.query(document, "#primary-launch-link[href='/login']")) == 1
    assert Enum.count(LazyHTML.query(document, "#register-link[href='/register']")) == 1
    assert Enum.count(LazyHTML.query(document, "#hero-register-link[href='/register']")) == 1
    assert Enum.count(LazyHTML.query(document, "img[src='/images/landing/sol-approach.svg']")) == 1
    refute html =~ "Umbrella prototype"
    refute html =~ "Canvas 2D"
    refute html =~ "sector 1-1"
  end
end
