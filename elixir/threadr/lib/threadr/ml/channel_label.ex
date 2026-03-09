defmodule Threadr.ML.ChannelLabel do
  @moduledoc """
  Shared formatting for bot-visible channel labels.
  """

  @spec format(String.t() | nil) :: String.t()
  def format(nil), do: "#unknown"

  def format(channel_name) when is_binary(channel_name) do
    trimmed = String.trim(channel_name)

    cond do
      trimmed == "" -> "#unknown"
      String.starts_with?(trimmed, "#") -> trimmed
      true -> "#" <> trimmed
    end
  end

  def format(channel_name), do: channel_name |> to_string() |> format()
end
