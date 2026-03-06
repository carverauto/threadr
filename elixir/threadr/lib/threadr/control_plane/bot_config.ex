defmodule Threadr.ControlPlane.BotConfig do
  @moduledoc """
  Normalization, validation, and redaction helpers for tenant-managed bot
  configuration.
  """

  @platforms ~w(discord irc)

  @platform_envs %{
    "irc" => %{
      required: ~w(THREADR_IRC_HOST THREADR_IRC_NICK),
      optional: ~w(
        THREADR_IRC_PASSWORD
        THREADR_IRC_PORT
        THREADR_IRC_REALNAME
        THREADR_IRC_SSL
        THREADR_IRC_USER
      ),
      legacy: %{
        "host" => "THREADR_IRC_HOST",
        "server" => "THREADR_IRC_HOST",
        "nick" => "THREADR_IRC_NICK",
        "password" => "THREADR_IRC_PASSWORD",
        "port" => "THREADR_IRC_PORT",
        "realname" => "THREADR_IRC_REALNAME",
        "ssl" => "THREADR_IRC_SSL",
        "user" => "THREADR_IRC_USER"
      }
    },
    "discord" => %{
      required: ~w(THREADR_DISCORD_TOKEN),
      optional: ~w(THREADR_DISCORD_APPLICATION_ID THREADR_DISCORD_PUBLIC_KEY),
      legacy: %{
        "application_id" => "THREADR_DISCORD_APPLICATION_ID",
        "public_key" => "THREADR_DISCORD_PUBLIC_KEY",
        "token" => "THREADR_DISCORD_TOKEN"
      }
    }
  }

  @sensitive_env_keys MapSet.new([
                        "THREADR_DISCORD_TOKEN",
                        "THREADR_IRC_PASSWORD"
                      ])

  def platform_schemas do
    Map.new(@platforms, fn platform ->
      rules = Map.fetch!(@platform_envs, platform)

      channel_format =
        case platform do
          "irc" -> "irc-channel"
          "discord" -> "discord-channel-id"
        end

      {platform,
       %{
         "platform" => platform,
         "required_env" => rules.required,
         "optional_env" => rules.optional,
         "legacy_settings" => rules.legacy |> Map.keys() |> Enum.sort(),
         "channel_format" => channel_format,
         "supports_image_override" => true
       }}
    end)
  end

  def normalize_and_validate(platform, channels, settings) do
    with {:ok, platform} <- normalize_platform(platform),
         {:ok, channels} <- normalize_channels(platform, channels),
         {:ok, settings} <- normalize_settings(platform, settings),
         :ok <- validate_channels(platform, channels),
         :ok <- validate_settings(platform, settings) do
      {:ok, %{platform: platform, channels: channels, settings: settings}}
    end
  end

  def normalize_platform(value) when is_binary(value) do
    platform =
      value
      |> String.trim()
      |> String.downcase()

    if platform in @platforms do
      {:ok, platform}
    else
      {:error, {:platform, "must be one of: #{Enum.join(@platforms, ", ")}"}}
    end
  end

  def normalize_platform(_value) do
    {:error, {:platform, "must be one of: #{Enum.join(@platforms, ", ")}"}}
  end

  def image(settings) when is_map(settings) do
    Map.get(settings, "image") || Map.get(settings, :image)
  end

  def env(settings) when is_map(settings) do
    settings
    |> Map.get("env", Map.get(settings, :env, %{}))
    |> stringify_map()
  end

  def redact_settings(settings) when is_map(settings) do
    settings = stringify_map(settings)

    env =
      settings
      |> env()
      |> Map.new(fn {key, value} ->
        if sensitive_env_key?(key) do
          {key, "[REDACTED]"}
        else
          {key, value}
        end
      end)

    settings
    |> Map.put("env", env)
  end

  def redact_settings(_settings), do: %{}

  defp normalize_channels(platform, channels) when is_list(channels) do
    normalized =
      channels
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    if normalized == [] do
      {:error, {:channels, "must include at least one #{platform} channel"}}
    else
      {:ok, normalized}
    end
  end

  defp normalize_channels(platform, _channels) do
    {:error, {:channels, "must include at least one #{platform} channel"}}
  end

  defp normalize_settings(platform, settings) do
    platform_rules = Map.fetch!(@platform_envs, platform)
    settings = stringify_map(settings || %{})

    allowed_keys = ["env", "image"] ++ Map.keys(platform_rules.legacy)

    case Enum.reject(Map.keys(settings), &(&1 in allowed_keys)) do
      [] ->
        env =
          settings
          |> Map.get("env", %{})
          |> stringify_map()
          |> merge_legacy_keys(settings, platform_rules.legacy)

        image =
          case Map.get(settings, "image") do
            nil -> nil
            value -> to_string(value)
          end

        {:ok,
         %{}
         |> maybe_put("image", image)
         |> Map.put("env", env)}

      unexpected ->
        {:error,
         {:settings, "contains unsupported keys: #{Enum.join(Enum.sort(unexpected), ", ")}"}}
    end
  end

  defp validate_channels("irc", channels) do
    case Enum.find(channels, &(not Regex.match?(~r/^[#&+!][^\s,]+$/, &1))) do
      nil -> :ok
      invalid -> {:error, {:channels, "contains invalid IRC channel #{inspect(invalid)}"}}
    end
  end

  defp validate_channels("discord", channels) do
    case Enum.find(channels, &(not Regex.match?(~r/^\d+$/, &1))) do
      nil -> :ok
      invalid -> {:error, {:channels, "contains invalid Discord channel #{inspect(invalid)}"}}
    end
  end

  defp validate_settings(platform, settings) do
    env = env(settings)
    rules = Map.fetch!(@platform_envs, platform)
    allowed_envs = MapSet.new(rules.required ++ rules.optional)

    with :ok <- validate_required_envs(rules.required, env),
         :ok <- validate_supported_envs(allowed_envs, env) do
      :ok
    end
  end

  defp validate_required_envs(required_envs, env) do
    case Enum.find(required_envs, &blank?(Map.get(env, &1))) do
      nil ->
        :ok

      key ->
        {:error, {:settings, "missing required env #{key}"}}
    end
  end

  defp validate_supported_envs(allowed_envs, env) do
    case Enum.find(Map.keys(env), &(not MapSet.member?(allowed_envs, &1))) do
      nil ->
        :ok

      key ->
        {:error, {:settings, "contains unsupported env #{key}"}}
    end
  end

  defp merge_legacy_keys(env, settings, legacy_map) do
    Enum.reduce(legacy_map, env, fn {legacy_key, env_key}, acc ->
      cond do
        Map.has_key?(acc, env_key) ->
          acc

        blank?(Map.get(settings, legacy_key)) ->
          acc

        true ->
          Map.put(acc, env_key, normalize_env_value(Map.fetch!(settings, legacy_key)))
      end
    end)
  end

  defp normalize_env_value(value) when is_binary(value), do: String.trim(value)
  defp normalize_env_value(value), do: to_string(value)

  defp sensitive_env_key?(key), do: MapSet.member?(@sensitive_env_keys, key)

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      string_key = to_string(key)

      normalized_value =
        case value do
          nested when is_map(nested) -> stringify_map(nested)
          nil -> nil
          other -> normalize_env_value(other)
        end

      {string_key, normalized_value}
    end)
  end

  defp stringify_map(_), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false
end
