defmodule MinionWeb.TeamLive do
  use MinionWeb, :live_view

  import MinionWeb.AlertComponents, only: [local_time: 1]

  alias Minion.Accounts
  alias Minion.Accounts.Person
  alias MinionWeb.{PersonLive, TeamsLive}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    team = Accounts.get_team!(id)

    {:ok,
     socket
     |> assign(page_title: team.name, rules: Accounts.list_team_rules(team.id), new_key: nil)
     |> assign(new_person: to_form(Accounts.change_person(%Person{}), as: :person))
     |> load(team)}
  end

  defp load(socket, team) do
    assign(socket,
      team: team,
      form: to_form(Accounts.change_team(team), as: :team),
      minutes: minutes(team.auto_resolve_after)
    )
  end

  defp minutes(settings) do
    Map.new(["warning", "info"], fn severity ->
      value = settings[severity]
      {severity, if(is_integer(value), do: to_string(div(value, 60)), else: "")}
    end)
  end

  @impl true
  def handle_event("validate", %{"team" => params}, socket) do
    form =
      socket.assigns.team
      |> Accounts.change_team(team_attrs(params))
      |> Map.put(:action, :validate)
      |> to_form(as: :team)

    {:noreply, assign(socket, form: form, minutes: Map.take(params, ["warning", "info"]))}
  end

  def handle_event("save", %{"team" => params}, socket) do
    case Accounts.update_team(socket.assigns.team, team_attrs(params)) do
      {:ok, team} ->
        {:noreply, socket |> load(team) |> put_flash(:info, "Saved #{team.name}.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :team))}
    end
  end

  def handle_event("generate_key", _params, socket) do
    {:ok, team, key} = Accounts.generate_ingest_key(socket.assigns.team)
    {:noreply, socket |> load(Accounts.get_team!(team.id)) |> assign(:new_key, key)}
  end

  def handle_event("add_person", %{"person" => params}, socket) do
    case Accounts.create_person(Map.put(params, "team_id", socket.assigns.team.id)) do
      {:ok, person} ->
        {:noreply,
         socket
         |> put_flash(:info, "Added #{person.name}. Set how they want to be notified.")
         |> push_navigate(to: ~p"/people/#{person.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, new_person: to_form(changeset, as: :person))}
    end
  end

  defp team_attrs(params) do
    auto_resolve_after =
      for severity <- ["warning", "info"],
          value = String.trim(params[severity] || ""),
          value != "",
          into: %{} do
        case Integer.parse(value) do
          {minutes, ""} when minutes > 0 -> {severity, minutes * 60}
          _ -> {severity, value}
        end
      end

    params
    |> Map.take(["name", "oncall_person_id"])
    |> Map.put("auto_resolve_after", auto_resolve_after)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_person={@current_person} people={@people} active={:teams}>
      <.link
        navigate={~p"/teams"}
        id="back-to-teams"
        class="inline-flex items-center gap-1 text-sm text-base-content/60 hover:text-base-content"
      >
        <.icon name="hero-arrow-left-mini" class="size-4" /> Teams
      </.link>

      <div>
        <h1 id="team-name" class="text-2xl font-semibold tracking-tight">{@team.name}</h1>
        <p id="team-auto-resolve" class="mt-1 text-sm text-base-content/60">
          {TeamsLive.auto_resolve_text(@team.auto_resolve_after)}
        </p>
      </div>

      <div class="grid gap-10 lg:grid-cols-2">
        <section class="space-y-4">
          <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60">
            Members
          </h2>
          <ul id="members" class="divide-y divide-base-300 border border-base-300">
            <li :if={@team.members == []} class="p-4 text-sm text-base-content/50">
              Nobody yet. Add the first person below.
            </li>
            <li :for={person <- @team.members} id={"member-#{person.id}"}>
              <.link
                navigate={~p"/people/#{person.id}"}
                class="block p-4 transition-colors hover:bg-base-200"
              >
                <span class="font-medium">{person.name}</span>
                <span
                  :if={@team.oncall_person_id == person.id}
                  class="ml-2 badge badge-sm badge-primary"
                >
                  on call
                </span>
                <span class="mt-1 block text-sm text-base-content/60">
                  Critical: {PersonLive.describe(critical_entries(person))}
                </span>
              </.link>
            </li>
          </ul>

          <.form for={@new_person} id="add-person-form" phx-submit="add_person" class="space-y-2">
            <h3 class="text-sm font-semibold">Add a person</h3>
            <div class="grid gap-3 sm:grid-cols-2">
              <.input field={@new_person[:name]} label="Name" />
              <.input field={@new_person[:email]} type="email" label="Email" />
            </div>
            <button id="add-person" type="submit" class="btn btn-sm btn-outline">
              Add and set notifications
            </button>
          </.form>
        </section>

        <section class="space-y-4">
          <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60">
            Settings
          </h2>
          <.form for={@form} id="team-form" phx-change="validate" phx-submit="save" class="space-y-3">
            <.input field={@form[:name]} label="Name" />
            <.input
              field={@form[:oncall_person_id]}
              type="select"
              label="On call"
              prompt="Nobody"
              options={Enum.map(@team.members, &{&1.name, &1.id})}
            />
            <fieldset class="space-y-2">
              <legend class="text-sm">
                Resolve quiet alerts automatically after (minutes, empty for never)
              </legend>
              <div class="grid grid-cols-2 gap-3">
                <.input
                  id="team-warning-minutes"
                  name="team[warning]"
                  value={@minutes["warning"]}
                  type="number"
                  min="1"
                  label="Warning"
                />
                <.input
                  id="team-info-minutes"
                  name="team[info]"
                  value={@minutes["info"]}
                  type="number"
                  min="1"
                  label="Info"
                />
              </div>
              <p class="text-xs text-base-content/50">Critical alerts never resolve themselves.</p>
              <p :if={@form.errors[:auto_resolve_after]} class="text-sm text-error">
                {elem(@form.errors[:auto_resolve_after], 0)}
              </p>
            </fieldset>
            <div class="flex justify-end">
              <button id="team-save" type="submit" class="btn btn-primary">Save</button>
            </div>
          </.form>

          <section id="ingest-key" class="space-y-3 pt-4">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60">
              Webhook key
            </h2>
            <p class="text-sm text-base-content/70">
              Send it as <code class="font-mono text-xs">Authorization: Bearer &lt;key&gt;</code>
              when posting to <code class="font-mono text-xs">/ingest/&lt;source&gt;</code>.
            </p>
            <p :if={@team.ingest_key_hint && !@new_key} id="ingest-key-status" class="text-sm">
              Key ending <span class="font-mono">…{@team.ingest_key_hint}</span>, created
              <.local_time id="ingest-key-created" at={@team.ingest_key_created_at} />.
            </p>
            <p :if={!@team.ingest_key_hint} id="ingest-key-missing" class="text-sm font-medium">
              No key yet: posts for this team are refused until you generate one.
            </p>
            <div
              :if={@new_key}
              id="new-ingest-key"
              class="space-y-2 border-l-4 border-primary bg-base-200 p-4 text-sm"
            >
              <p class="font-medium">Copy this key now. It is not shown again.</p>
              <code id="new-ingest-key-value" class="block break-all font-mono text-xs">{@new_key}</code>
              <p class="text-xs text-base-content/60">Try it:</p>
              <pre class="overflow-x-auto font-mono text-xs">curl -X POST {url(~p"/ingest/my-service")} \
      -H "Authorization: Bearer {@new_key}" \
      -H "content-type: application/json" -d '&lbrace;"type":"TEST"&rbrace;'</pre>
            </div>
            <button
              id="generate-ingest-key"
              type="button"
              phx-click="generate_key"
              data-confirm={
                @team.ingest_key_hint &&
                  "Systems using the current key will be refused until they switch to the new one. Continue?"
              }
              class="btn btn-sm btn-outline"
            >
              {if @team.ingest_key_hint, do: "Generate a new key", else: "Generate key"}
            </button>
          </section>

          <h2 class="pt-4 text-sm font-semibold uppercase tracking-wider text-base-content/60">
            Rules this team owns
          </h2>
          <ul id="team-rules" class="space-y-1 text-sm">
            <li :if={@rules == []} class="text-base-content/50">
              None yet. <.link navigate={~p"/rules/new"} class="underline">Create a rule</.link>
            </li>
            <li :for={rule <- @rules}>
              <.link navigate={~p"/rules/#{rule.id}"} class="underline hover:text-base-content">
                {rule.name}
              </.link>
              <span :if={!rule.enabled} class="text-base-content/50">(off)</span>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp critical_entries(person) do
    case person.preferences do
      %{"critical" => entries} when is_list(entries) -> Enum.filter(entries, &is_map/1)
      _ -> []
    end
  end
end
