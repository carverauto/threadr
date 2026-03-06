defmodule ThreadrWeb.ApiKeyLive.Index do
  use ThreadrWeb, :live_view

  alias Threadr.ControlPlane.Service

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:new_api_key, nil)
     |> assign(:api_keys, load_api_keys(socket.assigns.current_user))}
  end

  @impl true
  def handle_event("create", %{"api_key" => %{"name" => name}}, socket) do
    case Service.create_api_key(socket.assigns.current_user, %{name: String.trim(name)}) do
      {:ok, _api_key, plaintext} ->
        {:noreply,
         socket
         |> put_flash(:info, "API key created")
         |> assign(:new_api_key, plaintext)
         |> assign(:api_keys, load_api_keys(socket.assigns.current_user))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "API key creation failed: #{inspect(reason)}")}
    end
  end

  def handle_event("revoke", %{"id" => api_key_id}, socket) do
    case Service.revoke_api_key(socket.assigns.current_user, api_key_id) do
      {:ok, _api_key} ->
        {:noreply,
         socket
         |> put_flash(:info, "API key revoked")
         |> assign(:api_keys, load_api_keys(socket.assigns.current_user))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "API key does not belong to the current user")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "API key revocation failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="space-y-6">
        <.header>
          API Keys
          <:subtitle>
            Create personal API keys for tenant-facing automation. Plaintext secrets are shown once.
          </:subtitle>
          <:actions>
            <.button navigate={~p"/control-plane/tenants"}>Tenants</.button>
          </:actions>
        </.header>

        <div class="text-sm text-base-content/70">
          Signed in as <span class="font-semibold">{@current_user.email}</span>
        </div>

        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <form phx-submit="create" class="flex flex-col gap-4 md:flex-row md:items-end">
              <div class="flex-1">
                <.input
                  name="api_key[name]"
                  label="Key name"
                  value=""
                  placeholder="CI automation"
                  required
                />
              </div>
              <.button class="btn btn-primary">Create API key</.button>
            </form>
          </div>
        </div>

        <div :if={@new_api_key} class="alert alert-warning">
          <div class="space-y-2">
            <div class="font-semibold">Copy this API key now.</div>
            <code class="block overflow-x-auto rounded bg-base-300 p-3 text-sm">{@new_api_key}</code>
          </div>
        </div>

        <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
          <.table id="api-keys" rows={@api_keys} row_id={&"api-key-#{&1.id}"}>
            <:col :let={api_key} label="Name">{api_key.name}</:col>
            <:col :let={api_key} label="Status">
              <span class={badge_class(api_key.revoked_at)}>{status_label(api_key.revoked_at)}</span>
            </:col>
            <:col :let={api_key} label="Created">
              {format_datetime(api_key.inserted_at)}
            </:col>
            <:col :let={api_key} label="Last Used">
              {format_datetime(api_key.last_used_at)}
            </:col>
            <:action :let={api_key}>
              <button
                :if={is_nil(api_key.revoked_at)}
                type="button"
                class="btn btn-sm btn-error"
                phx-click="revoke"
                phx-value-id={api_key.id}
              >
                Revoke
              </button>
            </:action>
          </.table>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp load_api_keys(current_user) do
    case Service.list_user_api_keys(current_user) do
      {:ok, api_keys} -> api_keys
      {:error, _reason} -> []
    end
  end

  defp status_label(nil), do: "active"
  defp status_label(_revoked_at), do: "revoked"

  defp badge_class(nil), do: "badge badge-success"
  defp badge_class(_revoked_at), do: "badge badge-error"

  defp format_datetime(nil), do: "Never"

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end
end
