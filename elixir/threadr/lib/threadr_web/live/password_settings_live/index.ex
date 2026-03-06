defmodule ThreadrWeb.PasswordSettingsLive.Index do
  use ThreadrWeb, :live_view

  alias Threadr.ControlPlane.Service

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:password_form, %{
       "current_password" => "",
       "password" => "",
       "password_confirmation" => ""
     })}
  end

  @impl true
  def handle_event("change", %{"password" => params}, socket) do
    {:noreply, assign(socket, :password_form, Map.merge(socket.assigns.password_form, params))}
  end

  def handle_event("submit", %{"password" => params}, socket) do
    case Service.rotate_password_for_user(socket.assigns.current_user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_user, user)
         |> assign(:password_form, %{
           "current_password" => "",
           "password" => "",
           "password_confirmation" => ""
         })
         |> put_flash(:info, "Password updated.")
         |> push_navigate(to: ~p"/control-plane/tenants")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Password update failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <section class="mx-auto max-w-xl space-y-6">
        <.header>
          Password Settings
          <:subtitle>
            {if @current_user.must_rotate_password,
              do: "Rotate your bootstrap password before using the control plane.",
              else: "Change your account password."}
          </:subtitle>
        </.header>

        <div class="card border border-base-300 bg-base-100 shadow-sm">
          <div class="card-body">
            <.form
              for={%{}}
              as={:password}
              phx-change="change"
              phx-submit="submit"
              class="space-y-4"
            >
              <.input
                name="password[current_password]"
                type="password"
                label="Current password"
                value={@password_form["current_password"]}
              />

              <.input
                name="password[password]"
                type="password"
                label="New password"
                value={@password_form["password"]}
              />

              <.input
                name="password[password_confirmation]"
                type="password"
                label="Confirm new password"
                value={@password_form["password_confirmation"]}
              />

              <div class="flex gap-2">
                <button class="btn btn-primary" type="submit">Update password</button>
                <.link
                  :if={!@current_user.must_rotate_password}
                  navigate={~p"/control-plane/tenants"}
                  class="btn btn-ghost"
                >
                  Cancel
                </.link>
              </div>
            </.form>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
