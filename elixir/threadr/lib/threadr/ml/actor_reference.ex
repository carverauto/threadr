defmodule Threadr.ML.ActorReference do
  @moduledoc """
  Shared actor reference resolution for tenant-scoped QA flows.
  """

  import Ecto.Query

  alias Threadr.Repo

  @question_stopwords MapSet.new([
                       "a",
                       "about",
                       "all",
                       "an",
                       "and",
                       "did",
                       "does",
                       "for",
                       "happened",
                       "have",
                       "has",
                       "how",
                       "in",
                       "is",
                       "it",
                       "last",
                       "month",
                       "people",
                       "said",
                       "talk",
                       "talked",
                       "that",
                       "the",
                       "this",
                       "to",
                       "today",
                       "was",
                       "week",
                       "were",
                       "what",
                       "when",
                       "where",
                       "who",
                       "why",
                       "with",
                       "yesterday"
                     ])

  @spec resolve(String.t(), String.t(), keyword()) ::
          {:ok, map()}
          | {:error, {:actor_not_found, String.t()} | {:ambiguous_actor, String.t(), [map()]}}
  def resolve(tenant_schema, raw_ref, opts \\ [])
      when is_binary(tenant_schema) and is_binary(raw_ref) and is_list(opts) do
    refs = actor_reference_candidates(raw_ref, opts)

    Enum.reduce_while(refs, {:error, {:actor_not_found, normalize(raw_ref)}}, fn ref, _acc ->
      case lookup(tenant_schema, ref) do
        {:ok, _actor} = result -> {:halt, result}
        {:error, {:ambiguous_actor, _, _}} = result -> {:halt, result}
        {:error, {:actor_not_found, _}} -> {:cont, {:error, {:actor_not_found, ref}}}
      end
    end)
  end

  @spec normalize(String.t()) :: String.t()
  def normalize(raw_ref) do
    raw_ref
    |> to_string()
    |> String.trim()
    |> String.trim_trailing("?")
    |> String.trim_trailing("!")
    |> String.trim_trailing(".")
    |> trim_matching_quotes()
    |> String.trim_leading("@")
    |> String.trim()
  end

  @spec find_mentions(String.t(), String.t(), keyword()) :: [map()]
  def find_mentions(tenant_schema, text, opts \\ [])
      when is_binary(tenant_schema) and is_binary(text) and is_list(opts) do
    text
    |> mention_candidates()
    |> Enum.reduce([], fn candidate, actors ->
      case resolve(tenant_schema, candidate, opts) do
        {:ok, actor} -> [actor | actors]
        _ -> actors
      end
    end)
    |> Enum.uniq_by(& &1.id)
  end

  @spec self_reference?(String.t()) :: boolean()
  def self_reference?(value) when is_binary(value) do
    String.downcase(normalize(value)) in ["i", "me", "myself"]
  end

  defp actor_reference_candidates(raw_ref, opts) do
    normalized = normalize(raw_ref)

    refs =
      if self_reference?(normalized) do
        requester_reference_candidates(opts) ++ [normalized]
      else
        [normalized, mention_external_id(normalized), last_token_candidate(normalized)]
      end

    refs
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp lookup(tenant_schema, ref) do
    handle_matches =
      from(a in "actors",
        where: fragment("lower(?) = lower(?)", a.handle, ^ref),
        select: %{
          id: a.id,
          handle: a.handle,
          display_name: a.display_name,
          external_id: a.external_id,
          platform: a.platform
        }
      )
      |> Repo.all(prefix: tenant_schema)
      |> Enum.map(&normalize_actor_match/1)

    case uniq_actor_matches(handle_matches) do
      [actor] ->
        {:ok, actor}

      [_ | _] = matches ->
        {:error, {:ambiguous_actor, ref, matches}}

      [] ->
        external_matches =
          from(a in "actors",
            where: a.external_id == ^discord_or_plain_external_id(ref),
            select: %{
              id: a.id,
              handle: a.handle,
              display_name: a.display_name,
              external_id: a.external_id,
              platform: a.platform
            }
          )
          |> Repo.all(prefix: tenant_schema)
          |> Enum.map(&normalize_actor_match/1)

        case uniq_actor_matches(external_matches) do
          [actor] ->
            {:ok, actor}

          [_ | _] = matches ->
            {:error, {:ambiguous_actor, ref, matches}}

          [] ->
            display_matches =
              from(a in "actors",
                where: not is_nil(a.display_name),
                where: fragment("lower(?) = lower(?)", a.display_name, ^ref),
                select: %{
                  id: a.id,
                  handle: a.handle,
                  display_name: a.display_name,
                  external_id: a.external_id,
                  platform: a.platform
                }
              )
              |> Repo.all(prefix: tenant_schema)
              |> Enum.map(&normalize_actor_match/1)

            case uniq_actor_matches(display_matches) do
              [actor] -> {:ok, actor}
              [_ | _] = matches -> {:error, {:ambiguous_actor, ref, matches}}
              [] -> {:error, {:actor_not_found, ref}}
            end
        end
    end
  end

  defp mention_external_id("<@" <> rest) do
    rest |> String.trim_trailing(">") |> String.trim_leading("!")
  end

  defp mention_external_id(_value), do: nil

  defp discord_or_plain_external_id(value), do: mention_external_id(value) || value

  defp requester_reference_candidates(opts) do
    [
      Keyword.get(opts, :requester_actor_handle),
      Keyword.get(opts, :requester_actor_display_name),
      Keyword.get(opts, :requester_external_id)
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&normalize/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp mention_candidates(text) do
    tokens =
      text
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9@<_!>'-]+/u, " ")
      |> String.split(~r/\s+/u, trim: true)

    if tokens == [] do
      []
    else
      max_size = min(length(tokens), 3)
      sizes = Range.new(max_size, 1, -1)

      for size <- sizes,
          start <- 0..(length(tokens) - size),
          candidate = tokens |> Enum.slice(start, size) |> Enum.join(" "),
          candidate != "",
          not MapSet.member?(@question_stopwords, candidate),
          not all_stopwords?(candidate) do
        candidate
      end
      |> Enum.uniq()
    end
  end

  defp all_stopwords?(candidate) do
    candidate
    |> String.split(~r/\s+/u, trim: true)
    |> Enum.all?(&MapSet.member?(@question_stopwords, &1))
  end

  defp last_token_candidate(value) do
    value
    |> String.split(~r/\s+/u, trim: true)
    |> List.last()
    |> case do
      ^value -> nil
      token -> token
    end
  end

  defp uniq_actor_matches(matches), do: Enum.uniq_by(matches, & &1.id)

  defp normalize_actor_match(match) do
    match
    |> Map.update!(:id, &normalize_identifier/1)
    |> Map.update(:external_id, nil, &normalize_identifier/1)
  end

  defp normalize_identifier(nil), do: nil

  defp normalize_identifier(value) when is_binary(value) do
    if String.valid?(value) do
      value
    else
      case Ecto.UUID.load(value) do
        {:ok, uuid} -> uuid
        :error -> Base.encode16(value, case: :lower)
      end
    end
  end

  defp normalize_identifier(value), do: to_string(value)

  defp trim_matching_quotes("\"" <> rest), do: rest |> String.trim_trailing("\"") |> String.trim()
  defp trim_matching_quotes("'" <> rest), do: rest |> String.trim_trailing("'") |> String.trim()
  defp trim_matching_quotes(value), do: value
end
