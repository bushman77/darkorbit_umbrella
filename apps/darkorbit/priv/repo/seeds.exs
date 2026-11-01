# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Darkorbit.Repo.insert!(%Darkorbit.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Darkorbit.Accounts

demo_accounts = [
  %{
    username: "demo_pilot",
    email: "demo_pilot@example.test",
    pilot_name: "Nova Runner",
    password: "launch-sector-11"
  },
  %{
    username: "wing_pilot",
    email: "wing_pilot@example.test",
    pilot_name: "Vega Wing",
    password: "launch-sector-11"
  }
]

Enum.each(demo_accounts, fn attrs ->
  case Accounts.get_by_username(attrs.username) do
    nil ->
      {:ok, account} = Accounts.register_account(attrs)
      verification_hash = get_in(account.verification, ["hash"])
      {:ok, _verified_account} = Accounts.verify_account(account.id, verification_hash)

    _existing_account ->
      :ok
  end
end)

IO.puts("Seeded playable pilots: demo_pilot and wing_pilot / launch-sector-11")
