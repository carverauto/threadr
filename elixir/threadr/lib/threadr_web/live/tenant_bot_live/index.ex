defmodule ThreadrWeb.TenantBotLive.Index do
  use ThreadrWeb, :live_view

  alias Threadr.ControlPlane.BotConfig
  alias Threadr.ControlPlane.Service
  alias ThreadrWeb.UserRoutes

  @default_platform "irc"
  @desired_states ~w(running stopped)

  @impl true
  def mount(params, _session, socket) do
    case params do
      %{"subject_name" => subject_name} ->
        case load_operator_workspace(socket, subject_name) do
          {:ok, tenant, membership} ->
            {:ok, mount_workspace(socket, tenant, membership, operator_view?: true)}

          {:error, :forbidden} ->
            {:ok,
             socket
             |> put_flash(:error, "You do not have permission to manage tenant bots")
             |> push_navigate(to: UserRoutes.home_path(socket.assigns.current_user))}

          {:error, _reason} ->
            {:ok,
             socket
             |> put_flash(:error, "Tenant not found")
             |> push_navigate(to: UserRoutes.home_path(socket.assigns.current_user))}
        end

      _other ->
        if Service.operator_admin?(socket.assigns.current_user) do
          {:ok, push_navigate(socket, to: ~p"/control-plane/tenants")}
        else
          case Service.ensure_personal_tenant_for_user(socket.assigns.current_user) do
            {:ok, tenant, membership} ->
              {:ok, mount_workspace(socket, tenant, membership, operator_view?: false)}

            {:error, _reason} ->
              {:ok,
               socket
               |> put_flash(:error, "Unable to open your bot workspace")
               |> push_navigate(to: ~p"/settings/api-keys")}
          end
        end
    end
  end

  @impl true
  def handle_event("change_bot", %{"bot" => params}, socket) do
    bot_form = normalize_bot_form(params, socket.assigns.bot_form)

    {:noreply,
     socket
     |> assign(:bot_form, bot_form)
     |> assign(:selected_platform_schema, selected_platform_schema(socket, bot_form))}
  end

  def handle_event("save_bot", %{"bot" => params}, socket) do
    bot_form = normalize_bot_form(params, socket.assigns.bot_form)

    socket =
      case save_bot(socket, bot_form) do
        {:ok, message} ->
          socket
          |> put_flash(:info, message)
          |> assign(
            :bots,
            load_bots(socket.assigns.current_user, socket.assigns.tenant.subject_name)
          )
          |> assign(:bot_form, default_bot_form())
          |> assign(
            :selected_platform_schema,
            selected_platform_schema(socket, default_bot_form())
          )
          |> assign(:editing_bot_id, nil)

        {:error, message} ->
          socket
          |> put_flash(:error, message)
          |> assign(:bot_form, bot_form)
          |> assign(:selected_platform_schema, selected_platform_schema(socket, bot_form))
      end

    {:noreply, socket}
  end

  def handle_event("edit_bot", %{"id" => bot_id}, socket) do
    case Enum.find(socket.assigns.bots, &(&1.id == bot_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Bot not found")}

      bot ->
        bot_form = bot_form(bot)

        {:noreply,
         socket
         |> assign(:editing_bot_id, bot.id)
         |> assign(:bot_form, bot_form)
         |> assign(:selected_platform_schema, selected_platform_schema(socket, bot_form))}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    bot_form = default_bot_form()

    {:noreply,
     socket
     |> assign(:editing_bot_id, nil)
     |> assign(:bot_form, bot_form)
     |> assign(:selected_platform_schema, selected_platform_schema(socket, bot_form))}
  end

  def handle_event("delete_bot", %{"id" => bot_id}, socket) do
    socket =
      case Service.delete_bot_for_user(
             socket.assigns.current_user,
             socket.assigns.tenant.subject_name,
             bot_id
           ) do
        :ok ->
          bot_form = default_bot_form()

          socket
          |> put_flash(:info, "Bot deleted")
          |> assign(
            :bots,
            load_bots(socket.assigns.current_user, socket.assigns.tenant.subject_name)
          )
          |> assign(:editing_bot_id, nil)
          |> assign(:bot_form, bot_form)
          |> assign(:selected_platform_schema, selected_platform_schema(socket, bot_form))

        {:error, reason} ->
          put_flash(socket, :error, bot_error_message(reason))
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <section class="space-y-6">
        <.header>
          {if @operator_view?, do: "Tenant Bots", else: "My Bots"}
          <:subtitle>
            {if @operator_view?,
              do: "Create, update, and retire IRC or Discord bots for #{@tenant.name}.",
              else: "Create, update, and retire your IRC or Discord bots."}
          </:subtitle>
          <:actions :if={@operator_view?}>
            <div class="flex gap-2">
              <.button navigate={~p"/control-plane/tenants"}>Tenants</.button>
              <.button navigate={~p"/control-plane/tenants/#{@tenant.subject_name}/history"}>
                History
              </.button>
              <.button navigate={~p"/control-plane/tenants/#{@tenant.subject_name}/qa"}>
                QA
              </.button>
            </div>
          </:actions>
        </.header>

        <div class="grid gap-6 xl:grid-cols-[26rem_minmax(0,1fr)]">
          <div class="space-y-4">
            <div
              :if={@operator_view?}
              class="rounded-box border border-base-300 bg-base-100 p-5"
            >
              <div class="flex items-center justify-between gap-4">
                <div>
                  <div class="text-sm text-base-content/60">Tenant</div>
                  <div class="font-semibold">{@tenant.name}</div>
                  <div class="text-sm text-base-content/70">{@tenant.subject_name}</div>
                </div>
                <span class="badge badge-outline">{@membership_role}</span>
              </div>
            </div>

            <div class="rounded-box border border-base-300 bg-base-100 p-5">
              <div class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/50">
                {if @editing_bot_id, do: "Edit Bot", else: "Create Bot"}
              </div>
              <div class="mt-2 text-sm text-base-content/70">
                {if @operator_view?,
                  do:
                    "Tenant bots publish normalized chat events into JetStream and reconcile into controller-owned workload contracts.",
                  else:
                    "Your bots publish normalized chat events into JetStream and reconcile into controller-owned workload contracts."}
              </div>

              <.form
                for={%{}}
                as={:bot}
                id="tenant-bot-form"
                phx-change="change_bot"
                phx-submit="save_bot"
                class="mt-5 space-y-4"
              >
                <.input
                  name="bot[name]"
                  value={@bot_form["name"]}
                  label="Bot Name"
                  required
                  readonly={not is_nil(@editing_bot_id)}
                />

                <div class="grid gap-4 md:grid-cols-2">
                  <label class="fieldset">
                    <span class="label">Platform</span>
                    <select
                      id="tenant-bot-platform"
                      name="bot[platform]"
                      class="select select-bordered"
                      disabled={not is_nil(@editing_bot_id)}
                    >
                      <option
                        :for={{platform, schema} <- @platform_schemas}
                        value={platform}
                        selected={@bot_form["platform"] == platform}
                      >
                        {String.capitalize(schema["platform"])}
                      </option>
                    </select>
                  </label>

                  <label class="fieldset">
                    <span class="label">Desired State</span>
                    <select
                      id="tenant-bot-desired-state"
                      name="bot[desired_state]"
                      class="select select-bordered"
                    >
                      <option
                        :for={state <- @desired_states}
                        value={state}
                        selected={@bot_form["desired_state"] == state}
                      >
                        {String.capitalize(state)}
                      </option>
                    </select>
                  </label>
                </div>

                <div :if={@editing_bot_id} class="text-xs text-base-content/60">
                  Bot name and platform stay fixed after creation. Update desired state, channels, image,
                  and platform settings here.
                </div>

                <.input
                  type="textarea"
                  id="tenant-bot-channels"
                  name="bot[channels]"
                  value={@bot_form["channels"]}
                  label={"Channels (#{@selected_platform_schema["channel_format"]})"}
                  placeholder={channel_placeholder(@bot_form["platform"])}
                  required
                />

                <.input
                  id="tenant-bot-image"
                  name="bot[image]"
                  value={@bot_form["image"]}
                  label="Image Override"
                  placeholder="Optional custom bot image"
                />

                <%= if @bot_form["platform"] == "irc" do %>
                  <div class="grid gap-4 md:grid-cols-2">
                    <.input
                      id="tenant-bot-irc-host"
                      name="bot[irc_host]"
                      value={@bot_form["irc_host"]}
                      label="IRC Host"
                      required
                    />
                    <.input
                      id="tenant-bot-irc-nick"
                      name="bot[irc_nick]"
                      value={@bot_form["irc_nick"]}
                      label="IRC Nick"
                      required
                    />
                    <.input
                      id="tenant-bot-irc-port"
                      name="bot[irc_port]"
                      value={@bot_form["irc_port"]}
                      label="IRC Port"
                      placeholder="6667"
                    />
                    <.input
                      id="tenant-bot-irc-user"
                      name="bot[irc_user]"
                      value={@bot_form["irc_user"]}
                      label="IRC User"
                    />
                    <.input
                      id="tenant-bot-irc-realname"
                      name="bot[irc_realname]"
                      value={@bot_form["irc_realname"]}
                      label="IRC Realname"
                    />
                    <label class="fieldset">
                      <span class="label">IRC TLS</span>
                      <select
                        id="tenant-bot-irc-ssl"
                        name="bot[irc_ssl]"
                        class="select select-bordered"
                      >
                        <option value="false" selected={@bot_form["irc_ssl"] == "false"}>
                          false
                        </option>
                        <option value="true" selected={@bot_form["irc_ssl"] == "true"}>true</option>
                      </select>
                    </label>
                  </div>

                  <.input
                    id="tenant-bot-irc-password"
                    type="password"
                    name="bot[irc_password]"
                    value={@bot_form["irc_password"]}
                    label="IRC Password"
                  />
                <% else %>
                  <.input
                    id="tenant-bot-discord-token"
                    type="password"
                    name="bot[discord_token]"
                    value={@bot_form["discord_token"]}
                    label="Discord Token"
                    required
                  />

                  <div class="text-xs text-base-content/60">
                    Discord ingestion only needs the bot token and channel IDs. Interaction
                    webhook settings are not required here.
                  </div>
                <% end %>

                <div class="rounded-box bg-base-200 p-4 text-sm text-base-content/75">
                  <div class="font-semibold text-base-content">Platform Contract</div>
                  <div class="mt-1">
                    Required env: {Enum.join(@selected_platform_schema["required_env"], ", ")}
                  </div>
                  <div :if={@selected_platform_schema["optional_env"] != []} class="mt-1">
                    Optional env: {Enum.join(@selected_platform_schema["optional_env"], ", ")}
                  </div>
                </div>

                <div class="flex flex-wrap gap-2">
                  <.button id="tenant-bot-save" class="btn btn-primary">
                    {if @editing_bot_id, do: "Save Bot", else: "Create Bot"}
                  </.button>
                  <.button
                    :if={@editing_bot_id}
                    id="tenant-bot-cancel"
                    type="button"
                    class="btn btn-ghost"
                    phx-click="cancel_edit"
                  >
                    Cancel
                  </.button>
                </div>
              </.form>
            </div>
          </div>

          <div class="rounded-box border border-base-300 bg-base-100 p-5">
            <div class="flex items-center justify-between gap-4">
              <div>
                <div class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/50">
                  Bot Inventory
                </div>
                <div class="mt-2 text-sm text-base-content/70">
                  {if @operator_view?,
                    do: "Tenant-managed bot definitions and their latest desired or observed state.",
                    else: "Your bot definitions and their latest desired or observed state."}
                </div>
              </div>
              <span class="badge badge-outline">{length(@bots)} bots</span>
            </div>

            <div
              :if={@bots == []}
              class="mt-6 rounded-box bg-base-200 p-4 text-sm text-base-content/70"
            >
              No bots configured yet.
            </div>

            <div :if={@bots != []} class="mt-6 space-y-4">
              <article
                :for={bot <- @bots}
                id={"tenant-bot-#{bot.id}"}
                class="rounded-box border border-base-300 bg-base-100 p-4"
              >
                <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                  <div class="space-y-2">
                    <div class="flex flex-wrap items-center gap-2">
                      <div class="font-semibold">{bot.name}</div>
                      <span class="badge badge-outline">{String.capitalize(bot.platform)}</span>
                      <span class={badge_class(bot.status)}>{bot.status}</span>
                    </div>
                    <div class="text-xs text-base-content/60">{bot.id}</div>
                    <div class="text-sm text-base-content/70">
                      desired: {bot.desired_state}
                    </div>
                    <div class="text-sm text-base-content/70">
                      status reason: {status_reason_text(bot.status_reason)}
                    </div>
                  </div>

                  <div class="flex flex-wrap gap-2">
                    <.button
                      id={"tenant-bot-edit-#{bot.id}"}
                      class="btn btn-sm"
                      phx-click="edit_bot"
                      phx-value-id={bot.id}
                    >
                      Edit
                    </.button>
                    <.button
                      id={"tenant-bot-delete-#{bot.id}"}
                      class="btn btn-sm btn-error btn-outline"
                      phx-click="delete_bot"
                      phx-value-id={bot.id}
                      data-confirm={"Delete #{bot.name}?"}
                    >
                      Delete
                    </.button>
                  </div>
                </div>

                <div class="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
                  <div class="rounded-box bg-base-200 p-3">
                    <div class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/50">
                      Deployment
                    </div>
                    <div class="mt-1 break-all text-sm">
                      {bot.deployment_name || "pending assignment"}
                    </div>
                  </div>

                  <div class="rounded-box bg-base-200 p-3">
                    <div class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/50">
                      Observation
                    </div>
                    <div class="mt-1 text-sm">{format_timestamp(bot.last_observed_at)}</div>
                  </div>

                  <div class="rounded-box bg-base-200 p-3">
                    <div class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/50">
                      Generation
                    </div>
                    <div class="mt-1 text-sm">{generation_summary(bot)}</div>
                  </div>

                  <div class="rounded-box bg-base-200 p-3">
                    <div class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/50">
                      Observation Metadata
                    </div>
                    <div class="mt-1 break-words text-sm">
                      {status_metadata_summary(bot.status_metadata)}
                    </div>
                  </div>
                </div>

                <div class="mt-4 grid gap-4 xl:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)]">
                  <div>
                    <div class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/50">
                      Channels
                    </div>
                    <div class="mt-1 break-words text-sm">{Enum.join(bot.channels, ", ")}</div>
                  </div>

                  <div>
                    <div class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/50">
                      Settings
                    </div>
                    <div class="mt-1 break-words text-sm text-base-content/70">
                      {settings_summary(bot)}
                    </div>
                  </div>
                </div>

                <div
                  :if={bot.status in [:reconciling, "reconciling"]}
                  class="mt-4 rounded-box border border-info/30 bg-info/10 p-3 text-sm text-base-content/80"
                >
                  Waiting for the Kubernetes controller or observer to report status for this
                  deployment. If this does not change, check the `ThreadrBot` resource, the
                  Deployment rollout, and operator logs.
                </div>
              </article>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp load_bots(current_user, subject_name) do
    case Service.list_bots_for_user(current_user, subject_name) do
      {:ok, bots} -> bots
      {:error, _reason} -> []
    end
  end

  defp load_operator_workspace(socket, subject_name) do
    with {:ok, tenant, membership} <-
           Service.get_user_tenant_by_subject_name(socket.assigns.current_user, subject_name),
         :ok <- Service.authorize_manager_role(membership) do
      {:ok, tenant, membership}
    end
  end

  defp mount_workspace(socket, tenant, membership, opts) do
    operator_view? = Keyword.get(opts, :operator_view?, false)
    platform_schemas = BotConfig.platform_schemas()
    bot_form = default_bot_form()

    socket
    |> assign(:tenant, tenant)
    |> assign(:membership_role, membership.role)
    |> assign(:operator_view?, operator_view?)
    |> assign(:desired_states, @desired_states)
    |> assign(:bots, load_bots(socket.assigns.current_user, tenant.subject_name))
    |> assign(:platform_schemas, platform_schemas)
    |> assign(:bot_form, bot_form)
    |> assign(:selected_platform_schema, Map.fetch!(platform_schemas, bot_form["platform"]))
    |> assign(:editing_bot_id, nil)
  end

  defp save_bot(socket, bot_form) do
    attrs = bot_attrs(bot_form)

    case socket.assigns.editing_bot_id do
      nil ->
        case Service.create_bot_for_user(
               socket.assigns.current_user,
               socket.assigns.tenant.subject_name,
               attrs
             ) do
          {:ok, bot} -> {:ok, "Bot created: #{bot.name}"}
          {:error, reason} -> {:error, bot_error_message(reason)}
        end

      bot_id ->
        case Service.update_bot_for_user(
               socket.assigns.current_user,
               socket.assigns.tenant.subject_name,
               bot_id,
               attrs
             ) do
          {:ok, bot} -> {:ok, "Bot updated: #{bot.name}"}
          {:error, reason} -> {:error, bot_error_message(reason)}
        end
    end
  end

  defp default_bot_form do
    %{
      "name" => "",
      "platform" => @default_platform,
      "desired_state" => "running",
      "channels" => "",
      "image" => "",
      "irc_host" => "",
      "irc_nick" => "",
      "irc_password" => "",
      "irc_port" => "",
      "irc_realname" => "",
      "irc_ssl" => "false",
      "irc_user" => "",
      "discord_token" => "",
      "discord_application_id" => "",
      "discord_public_key" => ""
    }
  end

  defp normalize_bot_form(params, previous_form) do
    default_bot_form()
    |> Map.merge(previous_form)
    |> Map.merge(Map.new(params, fn {key, value} -> {to_string(key), normalize_value(value)} end))
  end

  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(value), do: to_string(value)

  defp selected_platform_schema(socket, bot_form) do
    Map.fetch!(socket.assigns.platform_schemas, bot_form["platform"])
  end

  defp bot_form(bot) do
    env = BotConfig.env(bot.settings)

    default_bot_form()
    |> Map.merge(%{
      "name" => bot.name || "",
      "platform" => bot.platform || @default_platform,
      "desired_state" => bot.desired_state || "running",
      "channels" => Enum.join(bot.channels || [], "\n"),
      "image" => BotConfig.image(bot.settings) || "",
      "irc_host" => env["THREADR_IRC_HOST"] || "",
      "irc_nick" => env["THREADR_IRC_NICK"] || "",
      "irc_password" => env["THREADR_IRC_PASSWORD"] || "",
      "irc_port" => env["THREADR_IRC_PORT"] || "",
      "irc_realname" => env["THREADR_IRC_REALNAME"] || "",
      "irc_ssl" => env["THREADR_IRC_SSL"] || "false",
      "irc_user" => env["THREADR_IRC_USER"] || "",
      "discord_token" => env["THREADR_DISCORD_TOKEN"] || "",
      "discord_application_id" => env["THREADR_DISCORD_APPLICATION_ID"] || "",
      "discord_public_key" => env["THREADR_DISCORD_PUBLIC_KEY"] || ""
    })
  end

  defp bot_attrs(bot_form) do
    %{
      name: blank_to_nil(bot_form["name"]),
      platform: blank_to_nil(bot_form["platform"]),
      desired_state: blank_to_nil(bot_form["desired_state"]),
      channels: parse_channels(bot_form["channels"]),
      settings: settings(bot_form)
    }
  end

  defp settings(%{"platform" => "irc"} = bot_form) do
    base_settings(bot_form)
    |> maybe_put("server", bot_form["irc_host"])
    |> maybe_put("nick", bot_form["irc_nick"])
    |> maybe_put("password", bot_form["irc_password"])
    |> maybe_put("port", bot_form["irc_port"])
    |> maybe_put("realname", bot_form["irc_realname"])
    |> maybe_put("ssl", bot_form["irc_ssl"])
    |> maybe_put("user", bot_form["irc_user"])
  end

  defp settings(%{"platform" => "discord"} = bot_form) do
    base_settings(bot_form)
    |> maybe_put("token", bot_form["discord_token"])
    |> maybe_put("application_id", bot_form["discord_application_id"])
    |> maybe_put("public_key", bot_form["discord_public_key"])
  end

  defp settings(bot_form), do: base_settings(bot_form)

  defp base_settings(bot_form) do
    %{}
    |> maybe_put("image", bot_form["image"])
  end

  defp parse_channels(nil), do: []

  defp parse_channels(value) do
    value
    |> String.split(~r/[\n,]/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp channel_placeholder("discord"), do: "123456789012345678"
  defp channel_placeholder(_platform), do: "#threadr"

  defp settings_summary(bot) do
    settings = BotConfig.redact_settings(bot.settings)
    image = BotConfig.image(settings)
    env = BotConfig.env(settings)

    summary =
      env
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, value} -> "#{key}=#{value}" end)
      |> Enum.join(", ")

    case {image, summary} do
      {nil, ""} -> "No platform settings"
      {nil, env_summary} -> env_summary
      {image_value, ""} -> "image=#{image_value}"
      {image_value, env_summary} -> "image=#{image_value}, #{env_summary}"
    end
  end

  defp status_reason_text(nil), do: "waiting for first observation"
  defp status_reason_text(""), do: "waiting for first observation"

  defp status_reason_text(reason) when is_binary(reason) do
    reason
    |> String.replace("_", " ")
  end

  defp status_reason_text(reason), do: inspect(reason)

  defp format_timestamp(nil), do: "not observed yet"
  defp format_timestamp(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_timestamp(value), do: to_string(value)

  defp generation_summary(bot) do
    "desired #{bot.desired_generation || 0} / observed #{bot.observed_generation || 0}"
  end

  defp status_metadata_summary(metadata) when metadata in [%{}, nil],
    do: "no observation metadata yet"

  defp status_metadata_summary(metadata) when is_map(metadata) do
    metadata
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {key, value} -> "#{key}=#{value}" end)
    |> Enum.join(", ")
  end

  defp status_metadata_summary(metadata), do: inspect(metadata)

  defp badge_class(:running), do: "badge badge-success"
  defp badge_class(:reconciling), do: "badge badge-info"
  defp badge_class(:stopped), do: "badge badge-neutral"
  defp badge_class(:degraded), do: "badge badge-warning"
  defp badge_class(:deleting), do: "badge badge-error badge-outline"
  defp badge_class(:error), do: "badge badge-error"
  defp badge_class(:pending), do: "badge badge-ghost"

  defp badge_class(status) when is_binary(status),
    do: badge_class(String.to_existing_atom(status))

  defp badge_class(_status), do: "badge badge-neutral"

  defp bot_error_message({field, message}) when is_binary(message),
    do: "#{humanize_field(field)} #{message}"

  defp bot_error_message(%Ash.Error.Invalid{errors: errors}) do
    errors
    |> Enum.map(&Exception.message/1)
    |> Enum.join(", ")
  end

  defp bot_error_message({:bot, :not_found, _}), do: "Bot not found"
  defp bot_error_message(:forbidden), do: "You do not have permission to manage bots"
  defp bot_error_message(reason), do: "Bot update failed: #{inspect(reason)}"

  defp humanize_field(field) do
    field
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
