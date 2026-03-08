defmodule Threadr.TimeWindow do
  @moduledoc """
  Structured baseline/comparison time windows used by compare flows.
  """

  @enforce_keys []
  defstruct [:since, :until]

  @type t :: %__MODULE__{
          since: DateTime.t() | NaiveDateTime.t() | nil,
          until: DateTime.t() | NaiveDateTime.t() | nil
        }

  @spec new(map() | keyword()) :: t()
  def new(attrs \\ %{})

  def new(attrs) when is_list(attrs) do
    %__MODULE__{
      since: Keyword.get(attrs, :since),
      until: Keyword.get(attrs, :until)
    }
  end

  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      since: Map.get(attrs, :since),
      until: Map.get(attrs, :until)
    }
  end

  @spec from_opts(keyword(), nil | :compare) :: t()
  def from_opts(opts, prefix \\ nil) when is_list(opts) do
    new(
      since: Keyword.get(opts, prefixed_key(prefix, :since)),
      until: Keyword.get(opts, prefixed_key(prefix, :until))
    )
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = window) do
    %{since: window.since, until: window.until}
  end

  @spec to_keyword(t()) :: keyword()
  def to_keyword(%__MODULE__{} = window) do
    []
    |> put_if_present(:since, window.since)
    |> put_if_present(:until, window.until)
    |> Enum.reverse()
  end

  defp prefixed_key(nil, key), do: key
  defp prefixed_key(:compare, :since), do: :compare_since
  defp prefixed_key(:compare, :until), do: :compare_until

  defp put_if_present(opts, _key, nil), do: opts
  defp put_if_present(opts, key, value), do: Keyword.put(opts, key, value)
end
