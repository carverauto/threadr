defmodule Threadr.ML.Extraction.NoopProvider do
  @moduledoc """
  Disabled extraction provider.
  """

  @behaviour Threadr.ML.Extraction.Provider

  @impl true
  def extract(_request, _opts), do: {:error, :extraction_provider_not_configured}
end
