defmodule MinionWeb.TeamsLive do
  use MinionWeb, :live_view

  alias Minion.Accounts
  alias Minion.Accounts.Team

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Teams")
     |> assign(new_team: to_form(Accounts.change_team(%Team{}), as: :team))
     |> load_teams()}
  end

  defp load_teams(socket),
    do: assign(socket, teams: Accounts.list_teams(), rule_counts: Accounts.rule_counts())

  @impl true
  def handle_event("create", %{"team" => params}, socket) do
    case Accounts.create_team(params) do
      {:ok, team} -> {:noreply, push_navigate(socket, to: ~p"/teams/#{team.id}")}
      {:error, changeset} -> {:noreply, assign(socket, new_team: to_form(changeset, as: :team))}
    end
  end

  @shown_members 4

  @spec member_names([map()]) :: String.t()
  def member_names(members) when length(members) <= @shown_members,
    do: Enum.map_join(members, ", ", & &1.name)

  def member_names(members) do
    shown = members |> Enum.take(@shown_members - 1) |> Enum.map_join(", ", & &1.name)
    shown <> " and #{length(members) - @shown_members + 1} others"
  end

  @spec auto_resolve_text(map()) :: String.t()
  def auto_resolve_text(settings) do
    parts =
      for severity <- ["warning", "info"], is_integer(settings[severity]) do
        "#{severity} after #{duration(settings[severity])} quiet"
      end

    if parts == [], do: "Never auto-resolves", else: "Auto-resolves " <> Enum.join(parts, ", ")
  end

  @spec duration(pos_integer()) :: String.t()
  def duration(seconds) when rem(seconds, 3600) == 0, do: plural(div(seconds, 3600), "hour")
  def duration(seconds) when rem(seconds, 60) == 0, do: plural(div(seconds, 60), "minute")
  def duration(seconds), do: plural(seconds, "second")

  defp plural(1, unit), do: "1 #{unit}"
  defp plural(count, unit), do: "#{count} #{unit}s"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_person={@current_person} people={@people} active={:teams}>
      <div>
        <h1 class="text-2xl font-semibold tracking-tight">Teams</h1>
        <p id="teams-explainer" class="mt-2 max-w-3xl text-sm text-base-content/70">
          A team owns rules and the alerts they raise.
        </p>
      </div>

      <div id="teams" class="grid gap-4 md:grid-cols-2">
        <.link
          :for={team <- @teams}
          id={"team-#{team.id}"}
          navigate={~p"/teams/#{team.id}"}
          class="block border border-base-300 p-5 transition-colors hover:bg-base-200"
        >
          <div class="flex items-baseline justify-between gap-3">
            <h2 class="text-lg font-semibold">{team.name}</h2>
            <span class="text-sm text-base-content/60">
              {plural(Map.get(@rule_counts, team.id, 0), "rule")}
            </span>
          </div>
          <p class="mt-2 text-sm">
            <span :if={team.members == []} class="text-base-content/50">No members yet</span>
            {member_names(team.members)}
          </p>
          <p class="mt-1 text-sm text-base-content/60">
            On call: {if team.oncall_person, do: team.oncall_person.name, else: "nobody"}
          </p>
          <p class="mt-1 text-sm text-base-content/60">
            {auto_resolve_text(team.auto_resolve_after)}
          </p>
        </.link>
      </div>

      <.form
        for={@new_team}
        id="new-team-form"
        phx-submit="create"
        class="flex max-w-md items-end gap-3"
      >
        <div class="flex-1">
          <.input field={@new_team[:name]} label="New team" placeholder="e.g. payments" />
        </div>
        <button id="create-team" type="submit" class="btn btn-primary mb-2">Create team</button>
      </.form>
    </Layouts.app>
    """
  end
end
