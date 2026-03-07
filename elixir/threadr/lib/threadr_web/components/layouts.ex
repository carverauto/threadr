defmodule ThreadrWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ThreadrWeb, :html
  alias Threadr.ControlPlane.Service

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_user, :map, default: nil, doc: "the current authenticated user, when present"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-[radial-gradient(circle_at_top,_rgba(249,115,22,0.1),_transparent_22%),linear-gradient(180deg,_oklch(98%_0_0)_0%,_oklch(96%_0.001_286.375)_45%,_oklch(94%_0.003_286.32)_100%)] text-base-content dark:bg-[radial-gradient(circle_at_top,_rgba(251,146,60,0.1),_transparent_18%),linear-gradient(180deg,_oklch(24%_0.015_255)_0%,_oklch(20%_0.012_254.09)_100%)]">
      <header class="sticky top-0 z-40 border-b border-base-300/60 bg-base-100/88 backdrop-blur">
        <div class="mx-auto flex max-w-7xl items-center justify-between gap-6 px-4 py-4 sm:px-6 lg:px-8">
          <div class="flex items-center gap-8">
            <a href="/" class="flex items-center gap-3">
              <img src={~p"/images/logo.svg"} width="34" />
              <div>
                <div class="text-sm font-black uppercase tracking-[0.24em] text-base-content">
                  Threadr
                </div>
                <div class="text-xs text-base-content/55">Tenant-scoped intelligence graph</div>
              </div>
            </a>

            <nav class="hidden items-center gap-2 md:flex">
              <.link
                :if={@current_user}
                navigate={~p"/control-plane/tenants"}
                class="btn btn-ghost btn-sm"
              >
                Tenants
              </.link>
              <.link
                :if={@current_user && Service.operator_admin?(@current_user)}
                navigate={~p"/control-plane/admin/llm"}
                class="btn btn-ghost btn-sm"
              >
                System LLM
              </.link>
              <.link
                :if={@current_user}
                navigate={~p"/settings/api-keys"}
                class="btn btn-ghost btn-sm"
              >
                API Keys
              </.link>
              <.link href={~p"/"} class="btn btn-ghost btn-sm">
                Overview
              </.link>
            </nav>
          </div>

          <div class="flex items-center gap-3">
            <div :if={@current_user} class="hidden text-right sm:block">
              <div class="text-sm font-semibold text-base-content">
                {@current_user.name || @current_user.email}
              </div>
              <div class="text-xs text-base-content/55">
                {@current_user.email}
              </div>
            </div>

            <.theme_toggle />

            <div :if={@current_user} class="flex items-center gap-2">
              <.link href={~p"/sign-out"} class="btn btn-outline btn-sm">
                Sign out
              </.link>
            </div>

            <div :if={!@current_user} class="flex items-center gap-2">
              <.link href={~p"/sign-in"} class="btn btn-ghost btn-sm">
                Sign in
              </.link>
              <.link href={~p"/register"} class="btn btn-primary btn-sm">
                Register
              </.link>
            </div>
          </div>
        </div>
      </header>

      <main class="px-4 py-8 sm:px-6 lg:px-8 lg:py-10">
        <div class="mx-auto max-w-7xl space-y-4">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
