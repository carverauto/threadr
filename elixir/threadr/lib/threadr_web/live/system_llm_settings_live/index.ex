defmodule ThreadrWeb.SystemLlmSettingsLive.Index do
  use ThreadrWeb, :live_view

  alias Threadr.ControlPlane.Service
  alias Threadr.ML.Generation.ProviderResolver

  @impl true
  def mount(_params, _session, socket) do
    with :ok <- Service.authorize_operator_admin(socket.assigns.current_user),
         {:ok, settings} <- Service.get_system_llm_config_for_user(socket.assigns.current_user) do
      settings_form = settings_form(settings)

      {:ok,
       socket
       |> assign(:settings_form, settings_form)
       |> assign(:provider_meta, provider_meta(settings_form["provider_name"]))
       |> assign(:api_key_configured, settings.api_key_configured)
       |> assign(:test_result, nil)}
    else
      {:error, :forbidden} ->
        {:ok,
         socket
         |> put_flash(:error, "You do not have permission to manage the system LLM")
         |> push_navigate(to: ~p"/control-plane/tenants")}

      {:error, reason} ->
        {:ok,
         socket
         |> put_flash(:error, "System LLM settings could not be loaded: #{inspect(reason)}")
         |> push_navigate(to: ~p"/control-plane/tenants")}
    end
  end

  @impl true
  def handle_event("change", %{"settings" => params}, socket) do
    settings_form = normalize_settings_form(socket.assigns.settings_form, params)

    {:noreply,
     socket
     |> assign(:settings_form, settings_form)
     |> assign(:provider_meta, provider_meta(settings_form["provider_name"]))}
  end

  def handle_event("submit", %{"settings" => params, "intent" => intent}, socket) do
    case intent do
      "save" ->
        case Service.upsert_system_llm_config_for_user(socket.assigns.current_user, params) do
          {:ok, settings} ->
            settings_form = settings_form(settings)

            {:noreply,
             socket
             |> put_flash(:info, "System LLM settings saved.")
             |> assign(:settings_form, settings_form)
             |> assign(:provider_meta, provider_meta(settings_form["provider_name"]))
             |> assign(:api_key_configured, settings.api_key_configured)}

          {:error, {:missing_required_field, field}} ->
            {:noreply, put_flash(socket, :error, "Missing required field: #{field}")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "System LLM update failed: #{inspect(reason)}")}
        end

      "test" ->
        case Service.test_system_llm_config_for_user(socket.assigns.current_user, params) do
          {:ok, result} ->
            {:noreply,
             socket
             |> clear_flash()
             |> assign(:test_result, result)}

          {:error, {:missing_required_field, field}} ->
            {:noreply, put_flash(socket, :error, "Missing required field: #{field}")}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "System LLM connection test failed: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <section class="space-y-6">
        <.header>
          System LLM Settings
          <:subtitle>
            Configure the operator-managed default LLM provider used when tenants do not supply an override.
          </:subtitle>
          <:actions>
            <div class="flex gap-2">
              <.button navigate={~p"/control-plane/tenants"}>Tenants</.button>
            </div>
          </:actions>
        </.header>

        <div class="grid gap-4 lg:grid-cols-[1.2fr_0.8fr]">
          <div class="card border border-base-300 bg-base-100 shadow-sm">
            <div class="card-body space-y-4">
              <.form
                for={%{}}
                as={:settings}
                phx-change="change"
                phx-submit="submit"
                class="space-y-4"
              >
                <div class="grid gap-4 md:grid-cols-2">
                  <label class="fieldset">
                    <span class="label">Provider</span>
                    <select
                      name="settings[provider_name]"
                      class="select select-bordered"
                      value={@settings_form["provider_name"]}
                    >
                      <option
                        :for={provider <- ProviderResolver.supported_provider_names()}
                        value={provider}
                        selected={@settings_form["provider_name"] == provider}
                      >
                        {provider}
                      </option>
                    </select>
                  </label>

                  <.input
                    name="settings[model]"
                    label="Model"
                    value={@settings_form["model"]}
                    placeholder={@provider_meta.model_placeholder}
                  />
                </div>

                <.input
                  name="settings[endpoint]"
                  label="Endpoint"
                  value={@settings_form["endpoint"]}
                  placeholder={@provider_meta.endpoint}
                />
                <p class="text-sm text-base-content/70">
                  Leave blank to use the default <code>{@provider_meta.provider}</code> endpoint:
                  <code>{@provider_meta.endpoint}</code>
                </p>

                <.input
                  name="settings[api_key]"
                  type="password"
                  label={api_key_label(@api_key_configured)}
                  value=""
                  placeholder={api_key_placeholder(@api_key_configured)}
                />

                <div class="grid gap-4 md:grid-cols-2">
                  <.input
                    name="settings[temperature]"
                    type="number"
                    step="0.1"
                    label="Temperature"
                    value={@settings_form["temperature"]}
                  />

                  <.input
                    name="settings[max_tokens]"
                    type="number"
                    label="Max tokens"
                    value={@settings_form["max_tokens"]}
                  />
                </div>

                <.input
                  name="settings[system_prompt]"
                  type="textarea"
                  label="System prompt"
                  value={@settings_form["system_prompt"]}
                  placeholder="Answer using tenant context and state uncertainty clearly."
                />

                <div class="flex flex-wrap gap-2">
                  <button class="btn btn-primary" type="submit" name="intent" value="save">
                    Save settings
                  </button>
                  <button class="btn" type="submit" name="intent" value="test">
                    Test connection
                  </button>
                </div>
              </.form>
            </div>
          </div>

          <div class="card border border-base-300 bg-base-200 shadow-sm">
            <div class="card-body space-y-3">
              <div class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
                Operator Scope
              </div>
              <p class="text-sm text-base-content/80">
                This provider is the control-plane default. Tenant managers can choose to inherit it
                or replace it with a tenant-specific override.
              </p>

                <div class="rounded-box bg-base-100 p-4 text-sm">
                <div class="font-semibold">Current saved provider</div>
                <div class="mt-1">{@settings_form["provider_name"]}</div>
                <div class="mt-2 text-base-content/70">
                  {@provider_meta.summary}
                </div>
                <div :if={@api_key_configured} class="mt-2 text-base-content/70">
                  System API key is stored.
                </div>
              </div>

              <div :if={@test_result} class="rounded-box bg-base-100 p-4 text-sm">
                <div class="font-semibold">Test result</div>
                <div class="mt-1 text-base-content/70">
                  {@test_result.provider} / {@test_result.model}
                </div>
                <div id="system-llm-test-result" class="mt-3 whitespace-pre-wrap">
                  {@test_result.content}
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp settings_form(settings) do
    %{
      "provider_name" => settings.provider_name || "openai",
      "endpoint" => settings.endpoint || "",
      "model" => settings.model || "",
      "temperature" => (settings.temperature && to_string(settings.temperature)) || "",
      "max_tokens" => (settings.max_tokens && to_string(settings.max_tokens)) || "",
      "system_prompt" => settings.system_prompt || "",
      "api_key" => ""
    }
  end

  defp api_key_label(true), do: "API key (leave blank to keep current key)"
  defp api_key_label(false), do: "API key"

  defp api_key_placeholder(true), do: "Stored key will be kept unless replaced"
  defp api_key_placeholder(false), do: "Paste system LLM API key"

  defp normalize_settings_form(existing, params) do
    previous_provider = existing["provider_name"] || "openai"
    merged = Map.merge(existing, params)
    provider = merged["provider_name"] || "openai"

    endpoint =
      case {Map.get(params, "endpoint"), Map.get(existing, "endpoint"), previous_provider != provider} do
        {"", _existing_endpoint, true} ->
          provider_meta(provider).endpoint

        {nil, existing_endpoint, true} ->
          if blank_or_default_endpoint?(existing_endpoint, previous_provider) do
            provider_meta(provider).endpoint
          else
            merged["endpoint"]
          end

        _ ->
          merged["endpoint"]
      end

    Map.put(merged, "endpoint", endpoint)
  end

  defp blank_or_default_endpoint?(nil, _provider), do: true
  defp blank_or_default_endpoint?("", _provider), do: true

  defp blank_or_default_endpoint?(endpoint, provider) do
    endpoint == provider_meta(provider).endpoint
  end

  defp provider_meta(provider_name) do
    provider = provider_name || "openai"

    %{
      provider: provider,
      endpoint: ProviderResolver.default_endpoint(provider),
      model_placeholder: model_placeholder(provider),
      summary: provider_summary(provider)
    }
  end

  defp model_placeholder("openai"), do: "gpt model id"
  defp model_placeholder("anthropic"), do: "claude model id"
  defp model_placeholder("gemini"), do: "gemini model id"
  defp model_placeholder(_provider), do: "model id"

  defp provider_summary("openai"), do: "Uses the OpenAI chat completions API."
  defp provider_summary("anthropic"), do: "Uses the Anthropic Messages API."
  defp provider_summary("gemini"), do: "Uses the Gemini generateContent API."
  defp provider_summary(_provider), do: "Uses the configured provider API."
end
