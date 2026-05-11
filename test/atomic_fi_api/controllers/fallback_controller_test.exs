defmodule AtomicFiApi.FallbackControllerTest do
  use AtomicFiWeb.ConnCase, async: true

  alias AtomicFiApi.FallbackController

  setup %{conn: conn} do
    conn =
      conn
      |> Plug.Conn.put_req_header("accept", "application/json")
      |> Phoenix.Controller.accepts(["json"])
      |> Phoenix.Controller.put_format(:json)

    %{conn: conn}
  end

  describe "call/2" do
    test "{:error, %Ecto.Changeset{}} renders 422 with error map", %{conn: conn} do
      changeset =
        %Ecto.Changeset{
          valid?: false,
          errors: [name: {"can't be blank", [validation: :required]}],
          data: %{},
          types: %{name: :string}
        }

      conn = FallbackController.call(conn, {:error, changeset})
      assert conn.status == 422
      assert json_response(conn, 422)
    end

    test "{:error, :unauthorized} renders 401", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :unauthorized})
      assert conn.status == 401
    end

    test "{:error, :forbidden} renders 403", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :forbidden})
      assert conn.status == 403
    end

    test "{:error, :not_found} renders 404", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :not_found})
      assert conn.status == 404
    end

    test "%Ecto.NoResultsError{} renders 404", %{conn: conn} do
      conn = FallbackController.call(conn, %Ecto.NoResultsError{message: "not found"})
      assert conn.status == 404
    end

    test "{:error, %Flop.Meta{errors: [...]}} renders 500 with flop details", %{conn: conn} do
      flop_meta = %Flop.Meta{errors: [page: ["must be positive"]]}
      conn = FallbackController.call(conn, {:error, flop_meta})
      assert conn.status == 500
      body = json_response(conn, 500)
      assert body["error"] == "Internal server error"
      assert body["details"]["flop_errors"] =~ "page"
    end

    test "{:error, unknown_atom} renders 422 with reason", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :some_unknown_reason})
      assert conn.status == 422
      body = json_response(conn, 422)
      assert body["error"] == "Processing error"
      assert body["message"] == "some_unknown_reason"
    end
  end
end
