defmodule Threadr.ML.Generation.NoopProvider do
  @moduledoc """
  Disabled generation provider used until a chat model backend is configured.
  """

  @behaviour Threadr.ML.Generation.Provider

  @impl true
  def complete(_request, _opts) do
    {:error, :generation_provider_not_configured}
  end
end
