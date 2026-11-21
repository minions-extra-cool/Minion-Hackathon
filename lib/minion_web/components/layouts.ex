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

  attr :active, :atom, default: nil, values: [nil, :dashboard, :rules, :teams]
  attr :current_person, :map, default: nil
  attr :people, :list, default: []

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="border-b border-base-300">
      <nav id="main-nav" class="flex items-center gap-8 px-6 py-3 lg:px-10">
        <.link navigate={~p"/"} id="home-logo" aria-label="Minion, go to the dashboard">
          <.logo class="h-[34.8px] w-auto text-base-content" />
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
        <.person_menu current_person={@current_person} people={@people} />
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

  attr :current_person, :map, default: nil
  attr :people, :list, default: []

  def person_menu(assigns) do
    ~H"""
    <div id="person-menu" class="dropdown dropdown-end ml-auto">
      <div
        id="person-menu-button"
        tabindex="0"
        role="button"
        class={[
          "btn btn-sm gap-2 font-normal",
          if(@current_person, do: "btn-ghost", else: "btn-outline")
        ]}
      >
        <.icon name="hero-user-circle-mini" class="size-5" />
        <span :if={@current_person} id="current-person-name">{@current_person.name}</span>
        <span :if={!@current_person}>Who are you?</span>
        <.icon name="hero-chevron-down-micro" class="size-4 text-base-content/50" />
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu z-40 mt-1 w-60 border border-base-300 bg-base-100 p-2 shadow-lg"
      >
        <li class="menu-title text-xs">
          {if @current_person, do: "Switch to", else: "Act as"}
        </li>
        <li :for={person <- @people} :if={!@current_person || person.id != @current_person.id}>
          <.link
            id={"act-as-#{person.id}"}
            href={~p"/session/person?#{[person_id: person.id]}"}
            method="post"
          >
            {person.name}
            <span :if={person.team} class="text-xs text-base-content/50">{person.team.name}</span>
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  attr :class, :any, default: nil

  def logo(assigns) do
    ~H"""
    <svg
      id="minion-logo"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="26 4 72 58"
      fill="none"
      role="img"
      aria-label="Minion"
      class={@class}
    >
      <path d="M28 20h17v8H28a4.5 4.5 0 0 0 0-8z" fill="currentColor" />
      <clipPath id="logo-monocle-glass">
        <circle cx="60" cy="24" r="12.5" />
      </clipPath>
      <circle cx="60" cy="24" r="5.5" fill="currentColor" />
      <g clip-path="url(#logo-monocle-glass)">
        <g class="logo-lid logo-lid-top">
          <rect class="logo-lid-skin" x="47" y="11" width="26" height="13" />
          <rect x="47" y="22.8" width="26" height="1.2" fill="currentColor" />
        </g>
        <g class="logo-lid logo-lid-bottom">
          <rect class="logo-lid-skin" x="47" y="24" width="26" height="13" />
          <rect x="47" y="24" width="26" height="1.2" fill="currentColor" />
        </g>
      </g>
      <circle cx="60" cy="24" r="15" stroke="currentColor" stroke-width="6" />
      <path d="M80.62 20H91a4 4 0 0 1 0 8H80.62A21 21 0 0 0 80.62 20z" fill="currentColor" />
      <path
        d="M33.12 55.55Q33.26 55.81 33.39 56.09Q33.52 56.38 33.63 56.67Q33.75 56.37 33.88 56.08Q34.01 55.8 34.15 55.53L36.72 50.47Q36.79 50.34 36.86 50.26Q36.93 50.19 37.02 50.16Q37.11 50.12 37.23 50.12Q37.34 50.11 37.49 50.11H39.27V60.13H37.22V54.37Q37.22 53.95 37.26 53.46L34.6 58.61Q34.48 58.85 34.27 58.98Q34.06 59.1 33.79 59.1H33.47Q33.21 59.1 33 58.98Q32.79 58.85 32.66 58.61L29.99 53.45Q30.02 53.69 30.04 53.93Q30.05 54.17 30.05 54.37V60.13H28V50.11H29.77Q29.93 50.11 30.04 50.12Q30.15 50.12 30.24 50.16Q30.33 50.19 30.4 50.26Q30.48 50.34 30.54 50.47L33.12 55.55ZM46.49 60.13H44.15V50.11H46.49ZM52.59 50.11Q52.75 50.11 52.85 50.12Q52.95 50.14 53.03 50.18Q53.12 50.21 53.19 50.28Q53.27 50.35 53.36 50.47L58.12 56.49Q58.1 56.2 58.08 55.92Q58.07 55.65 58.07 55.41V50.11H60.12V60.13H58.91Q58.64 60.13 58.45 60.05Q58.27 59.97 58.1 59.75L53.37 53.78Q53.39 54.04 53.41 54.29Q53.42 54.54 53.42 54.76V60.13H51.37V50.11H52.59ZM67.34 60.13H65V50.11H67.34ZM82.11 55.12Q82.11 56.2 81.74 57.14Q81.36 58.07 80.68 58.77Q80 59.46 79.04 59.85Q78.08 60.24 76.91 60.24Q75.74 60.24 74.78 59.85Q73.82 59.46 73.13 58.77Q72.45 58.07 72.07 57.14Q71.7 56.2 71.7 55.12Q71.7 54.03 72.07 53.09Q72.45 52.16 73.13 51.47Q73.82 50.78 74.78 50.39Q75.74 50 76.91 50Q78.08 50 79.04 50.4Q80 50.79 80.68 51.48Q81.36 52.17 81.74 53.1Q82.11 54.04 82.11 55.12ZM79.73 55.12Q79.73 54.37 79.54 53.78Q79.35 53.18 78.99 52.77Q78.62 52.36 78.1 52.14Q77.58 51.92 76.91 51.92Q76.24 51.92 75.71 52.14Q75.19 52.36 74.83 52.77Q74.46 53.18 74.27 53.78Q74.08 54.37 74.08 55.12Q74.08 55.87 74.27 56.46Q74.46 57.06 74.83 57.47Q75.19 57.88 75.71 58.1Q76.24 58.31 76.91 58.31Q77.58 58.31 78.1 58.1Q78.62 57.88 78.99 57.47Q79.35 57.06 79.54 56.46Q79.73 55.87 79.73 55.12ZM87.48 50.11Q87.63 50.11 87.73 50.12Q87.83 50.14 87.92 50.18Q88 50.21 88.07 50.28Q88.15 50.35 88.25 50.47L93.01 56.49Q92.98 56.2 92.96 55.92Q92.95 55.65 92.95 55.41V50.11H95V60.13H93.79Q93.52 60.13 93.34 60.05Q93.15 59.97 92.98 59.75L88.25 53.78Q88.27 54.04 88.29 54.29Q88.3 54.54 88.3 54.76V60.13H86.25V50.11H87.48Z"
        fill="currentColor"
      />
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
