defmodule Darkorbit.Repo do
  use Ecto.Repo,
    otp_app: :darkorbit,
    adapter: Ecto.Adapters.Postgres
end
