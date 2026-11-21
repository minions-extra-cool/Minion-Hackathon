defmodule MinionWeb.PersonLive do
  use MinionWeb, :live_view

  alias Minion.Accounts
  alias Minion.Accounts.Person

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    person = Accounts.get_person!(id)

    {:ok,
     socket
     |> assign(page_title: person.name, teams: Accounts.list_teams())
     |> load(person)}
  end

  defp load(socket, person) do
    assign(socket,
      person: person,
      form: to_form(Accounts.change_person(person)),
      prefs: working_copy(person.preferences)
    )
  end

  @impl true
  def handle_event("validate", params, socket) do
    form =
      socket.assigns.person
      |> Accounts.change_person(person_params(params))
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, form: form, prefs: parse_prefs(params["prefs"] || %{}))}
  end

  def handle_event("save", params, socket) do
    prefs = parse_prefs(params["prefs"] || %{})
    attrs = Map.put(person_params(params), "preferences", prefs)

    case Accounts.update_person(socket.assigns.person, attrs) do
      {:ok, person} ->
        {:noreply,
         socket
         |> load(person)
         |> assign(
           people: Accounts.list_people(),
           current_person: refreshed_current(socket, person)
         )
         |> put_flash(:info, "Saved #{person.name}'s profile and notifications.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset), prefs: prefs)}
    end
  end

  def handle_event("remove_discord", _params, socket) do
    {:ok, person} = Accounts.update_person(socket.assigns.person, %{discord_webhook_url: nil})

    {:noreply,
     socket |> assign(:person, person) |> put_flash(:info, "Removed the Discord webhook.")}
  end

  def handle_event("add_entry", %{"severity" => severity}, socket) do
    {:noreply,
     update(socket, :prefs, fn prefs ->
       Map.update!(prefs, severity, &(&1 ++ [%{"channels" => [], "hours" => nil}]))
     end)}
  end

  def handle_event("remove_entry", %{"severity" => severity, "index" => index}, socket) do
    index = String.to_integer(index)

    {:noreply,
     update(socket, :prefs, fn prefs ->
       Map.update!(prefs, severity, &List.delete_at(&1, index))
     end)}
  end

  def handle_event("move_up", %{"severity" => severity, "index" => index}, socket) do
    index = String.to_integer(index)

    {:noreply,
     update(socket, :prefs, fn prefs ->
       Map.update!(prefs, severity, fn entries ->
         {entry, rest} = List.pop_at(entries, index)
         List.insert_at(rest, max(index - 1, 0), entry)
       end)
     end)}
  end

  defp refreshed_current(%{assigns: %{current_person: %{id: id}}}, %{id: id} = person), do: person
  defp refreshed_current(socket, _person), do: socket.assigns.current_person

  defp person_params(params) do
    case params["person"] || %{} do
      %{"discord_webhook_url" => url} = person when url in [nil, ""] ->
        Map.delete(person, "discord_webhook_url")

      person ->
        person
    end
  end

  defp working_copy(preferences) do
    Map.new(Person.severities(), fn severity ->
      entries =
        case Map.get(preferences || %{}, severity) do
          list when is_list(list) -> Enum.filter(list, &is_map/1)
          _ -> []
        end

      {severity, Enum.map(entries, &Map.take(&1, ["channels", "hours"]))}
    end)
  end

  defp parse_prefs(params) do
    Map.new(Person.severities(), fn severity ->
      entries =
        (params[severity] || %{})
        |> Enum.sort_by(fn {index, _entry} -> String.to_integer(index) end)
        |> Enum.map(fn {_index, entry} -> parse_entry(entry) end)

      {severity, entries}
    end)
  end

  defp parse_entry(entry) do
    channels = (entry["channels"] || []) |> Enum.filter(&(&1 in Person.channels())) |> Enum.uniq()

    if entry["limited"] == "true",
      do: %{"channels" => channels, "hours" => [hour(entry["from"], 8), hour(entry["to"], 20)]},
      else: %{"channels" => channels}
  end

  defp hour(value, default) do
    case Integer.parse(to_string(value)) do
      {hour, ""} -> hour
      _ -> default
    end
  end

  @spec describe([map()]) :: String.t()
  def describe([]), do: "Shown in the feed only. No notifications."

  def describe(entries) do
    always_matches? = Enum.any?(entries, &(&1["hours"] == nil))

    entries
    |> Enum.map(fn entry ->
      channels = channels_text(entry["channels"])

      case entry["hours"] do
        [from, to] -> "#{channels} from #{clock(from)} to #{clock(to)} UTC"
        _ -> channels
      end
    end)
    |> then(&if(always_matches?, do: &1, else: &1 ++ ["feed only"]))
    |> Enum.join(", otherwise ")
    |> upcase_first()
  end

  defp upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest

  defp channels_text([]), do: "feed only"

  defp channels_text(channels),
    do: channels |> Enum.map(&Minion.Channels.label/1) |> Enum.join(" + ")

  defp severity_label(severity), do: upcase_first(severity)

  defp clock(hour), do: String.pad_leading(to_string(hour), 2, "0") <> ":00"

  defp severity_hint("critical"), do: "Something is broken right now."
  defp severity_hint("warning"), do: "Needs attention soon."
  defp severity_hint("info"), do: "Good to know."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_person={@current_person} people={@people} active={:teams}>
      <div class="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 id="person-name" class="text-2xl font-semibold tracking-tight">{@person.name}</h1>
          <p class="mt-1 text-sm text-base-content/60">
            <span :if={@current_person && @current_person.id == @person.id} id="this-is-you">
              This is you ·
            </span>
            <.link
              :if={@person.team}
              id="person-team"
              navigate={~p"/teams/#{@person.team.id}"}
              class="underline hover:text-base-content"
            >{@person.team.name}</.link>
            <span :if={!@person.team}>No team</span>
          </p>
        </div>
      </div>

      <.form for={@form} id="person-form" phx-change="validate" phx-submit="save" class="space-y-10">
        <section class="grid gap-4 sm:grid-cols-2">
          <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60 sm:col-span-2">
            Contact
          </h2>
          <.input field={@form[:name]} label="Name" />
          <.input
            field={@form[:team_id]}
            type="select"
            label="Team"
            prompt="No team"
            options={Enum.map(@teams, &{&1.name, &1.id})}
          />
          <.input field={@form[:email]} type="email" label="Email" />
          <.input field={@form[:phone]} type="tel" label="Phone (for SMS and calls)" />
          <div class="sm:col-span-2">
            <.input
              field={@form[:discord_webhook_url]}
              value=""
              type="password"
              label="Discord webhook URL"
              autocomplete="off"
              placeholder={
                if @person.discord_webhook_url,
                  do: "Saved. Paste a new URL to replace it.",
                  else: "https://discord.com/api/webhooks/…"
              }
            />
            <p
              :if={@person.discord_webhook_url}
              id="discord-saved"
              class="-mt-1 mb-1 inline-flex items-center gap-2 text-xs text-base-content/70"
            >
              <.icon name="hero-check-circle-micro" class="size-4 text-success" />
              A webhook is saved (hidden here).
              <button
                id="remove-discord"
                type="button"
                phx-click="remove_discord"
                class="underline hover:text-base-content"
              >
                Remove
              </button>
            </p>
            <p id="discord-help" class="-mt-1 text-xs text-base-content/50">
              In Discord: Server Settings → Integrations → Webhooks → New Webhook, pick a channel,
              then Copy Webhook URL. Treat it like a password: anyone with it can post there.
              Then tick Discord below for the severities you want.
            </p>
          </div>
        </section>

        <section class="space-y-6">
          <div>
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60">
              How to reach you
            </h2>
            <p class="mt-1 max-w-2xl text-sm text-base-content/60">
              For each severity, the first line whose hours match the current time wins.
              A line without hours always matches. Every alert is in the feed either way.
              A rule can still choose the channels for everyone it notifies.
            </p>
          </div>

          <div
            :for={severity <- Person.severities()}
            id={"prefs-#{severity}"}
            class="border border-base-300 p-5"
          >
            <div class="flex flex-wrap items-baseline justify-between gap-3">
              <h3 class="font-semibold">
                {severity_label(severity)}
                <span class="ml-2 text-sm font-normal text-base-content/50">
                  {severity_hint(severity)}
                </span>
              </h3>
              <p id={"prefs-#{severity}-summary"} class="text-sm text-base-content/70">
                {describe(@prefs[severity])}
              </p>
            </div>

            <ol class="mt-4 space-y-2">
              <li
                :for={{entry, index} <- Enum.with_index(@prefs[severity])}
                id={"prefs-#{severity}-#{index}"}
                class="flex flex-wrap items-center gap-x-5 gap-y-2 bg-base-200 px-4 py-3 text-sm"
              >
                <span class="w-5 text-base-content/50 tabular-nums">{index + 1}.</span>
                <input type="hidden" name={"prefs[#{severity}][#{index}][channels][]"} value="" />
                <label :for={channel <- Person.channels()} class="inline-flex items-center gap-2">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-sm"
                    name={"prefs[#{severity}][#{index}][channels][]"}
                    value={channel}
                    checked={channel in entry["channels"]}
                  />
                  {Minion.Channels.label(channel)}
                </label>
                <span class="mx-1 h-5 border-l border-base-300" />
                <input type="hidden" name={"prefs[#{severity}][#{index}][limited]"} value="false" />
                <label class="inline-flex items-center gap-2">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-sm"
                    name={"prefs[#{severity}][#{index}][limited]"}
                    value="true"
                    checked={entry["hours"] != nil}
                  /> Only between
                </label>
                <span :if={entry["hours"]} class="inline-flex items-center gap-2">
                  <select
                    name={"prefs[#{severity}][#{index}][from]"}
                    class="select select-sm w-24"
                    aria-label="From hour"
                  >
                    <option
                      :for={hour <- 0..23}
                      value={hour}
                      selected={hour == Enum.at(entry["hours"], 0)}
                    >
                      {clock(hour)}
                    </option>
                  </select>
                  and
                  <select
                    name={"prefs[#{severity}][#{index}][to]"}
                    class="select select-sm w-24"
                    aria-label="To hour"
                  >
                    <option
                      :for={hour <- 1..24}
                      value={hour}
                      selected={hour == Enum.at(entry["hours"], 1)}
                    >
                      {clock(hour)}
                    </option>
                  </select>
                  UTC
                </span>
                <span class="ml-auto flex items-center gap-1">
                  <button
                    :if={index > 0}
                    type="button"
                    id={"prefs-#{severity}-#{index}-up"}
                    phx-click="move_up"
                    phx-value-severity={severity}
                    phx-value-index={index}
                    class="btn btn-ghost btn-xs"
                    aria-label="Move up"
                  >
                    <.icon name="hero-arrow-up-micro" class="size-4" />
                  </button>
                  <button
                    type="button"
                    id={"prefs-#{severity}-#{index}-remove"}
                    phx-click="remove_entry"
                    phx-value-severity={severity}
                    phx-value-index={index}
                    class="btn btn-ghost btn-xs"
                    aria-label="Remove"
                  >
                    <.icon name="hero-x-mark-micro" class="size-4" />
                  </button>
                </span>
              </li>
            </ol>

            <button
              type="button"
              id={"prefs-#{severity}-add"}
              phx-click="add_entry"
              phx-value-severity={severity}
              class="btn btn-sm btn-ghost mt-3"
            >
              <.icon name="hero-plus-micro" class="size-4" />
              {if @prefs[severity] == [], do: "Notify me", else: "Add a fallback"}
            </button>
          </div>
        </section>

        <p :if={@form.errors[:preferences]} class="text-sm text-error">
          {elem(@form.errors[:preferences], 0)}
        </p>

        <div class="flex justify-end">
          <button id="person-save" type="submit" class="btn btn-primary">Save</button>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
