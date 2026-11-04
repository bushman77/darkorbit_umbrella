defmodule Core.Factions do
  @moduledoc """
  Pure policy for the independent planetary SOL factions.

  Each planet (including Pluto) has a faction ID identical to its SOL body ID.
  Standing is a server-owned integer from -100 to 100, with 0 meaning neutral.
  A wanted warrant is independent from standing: an allied pilot may still be
  wanted for an offence. These policies describe possible patrol responses;
  they do NOT initiate combat, interceptions or random encounters.

  The legacy MMO/EIC/VRU player company IDs (1..3) are unrelated and must
  never be silently interpreted as planetary faction reputations.
  """

  alias Core.Universe.Sol

  @type band :: :allied | :friendly | :neutral | :unfriendly | :hostile
  @type directive :: :assist | :clear | :observe | :inspect | :intercept | :pursue

  @spec all() :: [map()]
  def all do
    Sol.all()
    |> Enum.filter(&Sol.destination?(&1.id))
    |> Enum.map(fn body -> %{id: body.id, name: body.name, home_body_id: body.id} end)
  end

  @spec exists?(term()) :: boolean()
  def exists?(id) when is_binary(id), do: Sol.destination?(id)
  def exists?(_), do: false

  @doc "Classify server-owned standing, with a neutral default of zero."
  @spec band(term()) :: {:ok, band()} | {:error, :invalid_reputation}
  def band(value) when is_integer(value) and value >= -100 and value <= 100 do
    {:ok,
     cond do
       value >= 60 -> :allied
       value >= 20 -> :friendly
       value >= -19 -> :neutral
       value >= -59 -> :unfriendly
       true -> :hostile
     end}
  end

  def band(_), do: {:error, :invalid_reputation}

  @doc """
  Patrol directive for one faction. A directive is not an encounter result.

  `:wanted` can only be a boolean and overrides the diplomatic standing;
  the encounter director must still check detection, interception capability,
  and any escalation orders before forcing a ship out of cruise.
  """
  @spec patrol_directive(term(), keyword()) ::
          {:ok, %{band: band(), directive: directive()}} | {:error, atom()}
  def patrol_directive(reputation, opts \\ [])

  def patrol_directive(reputation, opts) when is_list(opts) do
    wanted = Keyword.get(opts, :wanted, false)

    with {:ok, standing} <- band(reputation),
         true <- is_boolean(wanted) do
      directive =
        if wanted do
          :pursue
        else
          case standing do
            :allied -> :assist
            :friendly -> :clear
            :neutral -> :observe
            :unfriendly -> :inspect
            :hostile -> :intercept
          end
        end

      {:ok, %{band: standing, directive: directive}}
    else
      false -> {:error, :invalid_wanted}
      error -> error
    end
  end

  def patrol_directive(_reputation, _opts), do: {:error, :invalid_wanted}
end
