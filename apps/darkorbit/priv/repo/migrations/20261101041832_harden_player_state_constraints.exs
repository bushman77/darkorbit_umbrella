defmodule Darkorbit.Repo.Migrations.HardenPlayerStateConstraints do
  use Ecto.Migration

  def up do
    alter table(:player_accounts) do
      modify :username, :string, null: false
      modify :email, :string, null: false
      modify :password_hash, :string, null: false
      modify :pilot_name, :string, null: false
      modify :faction_id, :integer, null: false
      modify :clan_id, :integer, null: false
      modify :session_id, :string, null: false
      modify :data, :map, null: false
      modify :verification, :map, null: false
      modify :old_pilot_names, :map, null: false
      modify :ship_id, :integer, null: false, default: 1
      modify :rank_id, :integer, null: false, default: 1
      modify :experience, :bigint, null: false, default: 0
      modify :honor, :bigint, null: false, default: 0
      modify :credits, :bigint, null: false, default: 0
      modify :uridium, :bigint, null: false, default: 0
      modify :level, :integer, null: false, default: 1
      modify :version, :string, null: false, default: "live"
    end

    create constraint(:player_accounts, :player_accounts_faction_id_range,
             check: "faction_id >= 0 AND faction_id <= 3"
           )

    create constraint(:player_accounts, :player_accounts_credits_non_negative,
             check: "credits >= 0"
           )

    create constraint(:player_accounts, :player_accounts_uridium_non_negative,
             check: "uridium >= 0"
           )

    create constraint(:player_accounts, :player_accounts_experience_non_negative,
             check: "experience >= 0"
           )

    create constraint(:player_accounts, :player_accounts_level_positive, check: "level >= 1")
    create constraint(:player_accounts, :player_accounts_ship_id_positive, check: "ship_id > 0")
    create constraint(:player_accounts, :player_accounts_rank_id_positive, check: "rank_id > 0")
    create constraint(:player_ships, :player_ships_ship_id_positive, check: "ship_id > 0")

    create constraint(:player_ship_loadouts, :player_ship_loadouts_config_no_range,
             check: "config_no IN (1, 2)"
           )
  end

  def down do
    drop_if_exists constraint(:player_ship_loadouts, :player_ship_loadouts_config_no_range)
    drop_if_exists constraint(:player_ships, :player_ships_ship_id_positive)
    drop_if_exists constraint(:player_accounts, :player_accounts_rank_id_positive)
    drop_if_exists constraint(:player_accounts, :player_accounts_ship_id_positive)
    drop_if_exists constraint(:player_accounts, :player_accounts_level_positive)
    drop_if_exists constraint(:player_accounts, :player_accounts_experience_non_negative)
    drop_if_exists constraint(:player_accounts, :player_accounts_uridium_non_negative)
    drop_if_exists constraint(:player_accounts, :player_accounts_credits_non_negative)
    drop_if_exists constraint(:player_accounts, :player_accounts_faction_id_range)

    alter table(:player_accounts) do
      modify :username, :string, null: true
      modify :email, :string, null: true
      modify :password_hash, :string, null: true
      modify :pilot_name, :string, null: true
      modify :faction_id, :integer, null: true
      modify :clan_id, :integer, null: true
      modify :session_id, :string, null: true
      modify :data, :map, null: true
      modify :verification, :map, null: true
      modify :old_pilot_names, :map, null: true
      modify :ship_id, :integer, null: true, default: 1
      modify :rank_id, :integer, null: true, default: 1
      modify :experience, :bigint, null: true, default: 0
      modify :honor, :bigint, null: true, default: 0
      modify :credits, :bigint, null: true, default: 0
      modify :uridium, :bigint, null: true, default: 0
      modify :level, :integer, null: true, default: 1
      modify :version, :string, null: true, default: "live"
    end
  end
end
