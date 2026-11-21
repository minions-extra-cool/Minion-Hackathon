defmodule MinionWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MinionWeb, :html

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
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :active, :atom, default: nil, values: [nil, :dashboard, :rules]

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="border-b border-base-300">
      <nav id="main-nav" class="flex items-center gap-8 px-6 py-3 lg:px-10">
        <.link navigate={~p"/"} id="home-logo" aria-label="Minion, go to the dashboard">
          <.logo class="h-6 w-auto text-base-content" />
        </.link>
        <ul class="flex items-center gap-1 text-sm">
          <li>
            <.link
              id="nav-dashboard"
              navigate={~p"/"}
              class={[
                "px-3 py-1.5 transition-colors hover:bg-base-200",
                @active == :dashboard && "bg-primary/60 font-medium hover:bg-primary/70"
              ]}
            >
              Dashboard
            </.link>
          </li>
          <li>
            <.link
              id="nav-rules"
              navigate={~p"/rules"}
              class={[
                "px-3 py-1.5 transition-colors hover:bg-base-200",
                @active == :rules && "bg-primary/60 font-medium hover:bg-primary/70"
              ]}
            >
              Rules
            </.link>
          </li>
        </ul>
      </nav>
    </header>

    <main class="px-6 py-8 lg:px-10">
      <div class="max-w-6xl space-y-6">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  attr :class, :any, default: nil

  def logo(assigns) do
    ~H"""
    <svg
      id="minion-logo"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="26 4 72 40"
      fill="none"
      role="img"
      aria-label="Minion"
      class={@class}
    >
      <path d="M28 20h17v8H28a4.5 4.5 0 0 0 0-8z" fill="currentColor" />
      <circle cx="60" cy="24" r="15" stroke="currentColor" stroke-width="6" />
      <circle cx="60" cy="24" r="5.5" fill="currentColor" />
      <path d="M80.62 20H91a4 4 0 0 1 0 8H80.62A21 21 0 0 0 80.62 20z" fill="currentColor" />
    </svg>
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
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
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
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
