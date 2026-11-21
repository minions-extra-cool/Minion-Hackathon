defmodule MinionWeb.RuleEditorLive do
  use MinionWeb, :live_view

  import MinionWeb.AlertComponents, only: [rule_light: 1]

  alias Minion.{Alerts, Rules}
  alias Minion.Rules.{ConditionTree, Draft, Matcher, Path, Rule, Template}

  @recent_events 20

  @impl true
  def mount(params, _session, socket) do
    owner_options = Rules.owner_options()
    recent = Alerts.list_recent(@recent_events)

    {rule, draft} =
      case socket.assigns.live_action do
        :edit ->
          rule = Rules.get_rule!(params["id"])
          {rule, Draft.from_rule(rule)}

        :new ->
          default_owner = owner_options |> List.first() |> then(&(&1 && elem(&1, 1)))
          {%Rule{}, Draft.new(default_owner)}
      end

    {:ok,
     socket
     |> assign(
       page_title: if(rule.id, do: "Edit #{rule.name}", else: "New rule"),
       rule: rule,
       draft: draft,
       mode: "visual",
       json_text: "",
       json_error: nil,
       errors: [],
       form: to_form(%{}),
       owner_options: owner_options,
       notify_options: Rules.notify_options(),
       recent_events: Enum.map(recent, &{&1.title, &1.id}),
       recent_samples: Map.new(recent, &{&1.id, &1.sample_event}),
       recent_paths: recent |> Enum.flat_map(&Path.list(&1.sample_event)) |> Enum.uniq()
     )
     |> put_test_text(initial_test_text(params, recent))}
  end

  defp initial_test_text(%{"from_alert" => id}, _recent) do
    id |> Alerts.get_alert!() |> Map.fetch!(:sample_event) |> Jason.encode!(pretty: true)
  rescue
    Ecto.NoResultsError -> ""
  end

  defp initial_test_text(_params, _recent), do: ""

  @impl true
  def handle_event("change", params, socket),
    do: {:noreply, update(socket, :draft, &Draft.put_params(&1, params))}

  def handle_event("add_condition", %{"path" => id}, socket),
    do:
      {:noreply,
       update_tree(socket, &ConditionTree.add_leaf(&1, ConditionTree.parse_path_id(id)))}

  def handle_event("add_group", _params, socket),
    do: {:noreply, update_tree(socket, &ConditionTree.add_group(&1, []))}

  def handle_event("remove", %{"path" => id}, socket),
    do:
      {:noreply,
       update_tree(socket, &ConditionTree.remove_at(&1, ConditionTree.parse_path_id(id)))}

  def handle_event("mode", %{"mode" => "json"}, socket) do
    json = socket.assigns.draft |> Draft.to_attrs() |> Jason.encode!(pretty: true)
    {:noreply, assign(socket, mode: "json", json_text: json, json_error: nil)}
  end

  def handle_event("mode", %{"mode" => "visual"}, socket) do
    with {:ok, attrs} <- decode_json(socket.assigns.json_text),
         {:ok, draft} <- Draft.from_attrs(attrs) do
      {:noreply, assign(socket, mode: "visual", draft: draft, json_error: nil, errors: [])}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           json_error:
             "The visual editor can't show this yet: " <>
               Enum.join(error_messages(changeset), "; ")
         )}

      {:error, message} ->
        {:noreply, assign(socket, json_error: message)}
    end
  end

  def handle_event("json_change", %{"json" => json}, socket),
    do: {:noreply, assign(socket, json_text: json, json_error: nil)}

  def handle_event("test", %{"_target" => ["recent"], "recent" => id}, socket) do
    socket = assign(socket, :recent_choice, id)

    case Map.fetch(socket.assigns.recent_samples, id) do
      {:ok, sample} -> {:noreply, put_test_text(socket, Jason.encode!(sample, pretty: true))}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("test", %{"event" => text}, socket),
    do: {:noreply, put_test_text(socket, text)}

  def handle_event("save", params, socket) do
    attrs =
      case socket.assigns.mode do
        "json" -> decode_json(params["json"] || socket.assigns.json_text)
        "visual" -> {:ok, socket.assigns.draft |> Draft.put_params(params) |> Draft.to_attrs()}
      end

    with {:ok, attrs} <- attrs,
         {:ok, rule} <- persist(socket.assigns.rule, attrs) do
      {:noreply,
       socket
       |> put_flash(:info, "Saved \"#{rule.name}\". It applies to new events right away.")
       |> push_navigate(to: ~p"/rules")}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, errors: error_messages(changeset))}

      {:error, message} ->
        {:noreply, assign(socket, json_error: message)}
    end
  end

  defp persist(%Rule{id: nil}, attrs), do: Rules.create_rule(attrs)
  defp persist(rule, attrs), do: Rules.update_rule(rule, attrs)

  defp update_tree(socket, fun),
    do: update(socket, :draft, &Map.update!(&1, "conditions", fun))

  defp decode_json(text) do
    case Jason.decode(text) do
      {:ok, %{} = attrs} -> {:ok, attrs}
      {:ok, _other} -> {:error, "The JSON must be an object describing the rule."}
      {:error, error} -> {:error, "Invalid JSON: #{Exception.message(error)}"}
    end
  end

  defp put_test_text(socket, text) do
    {env, error} =
      case String.trim(text) do
        "" -> {nil, nil}
        trimmed -> parse_test_event(trimmed)
      end

    assign(socket,
      test_text: text,
      test_env: env,
      test_error: error,
      recent_choice: Map.get(socket.assigns, :recent_choice, "")
    )
  end

  defp parse_test_event(text) do
    case Jason.decode(text) do
      {:ok, %{"payload" => _} = envelope} ->
        {Map.merge(%{"source" => "test", "source_type" => "http"}, envelope), nil}

      {:ok, payload} ->
        {%{"source" => "test", "source_type" => "http", "payload" => payload}, nil}

      {:error, _} ->
        {%{"source" => "test", "source_type" => "http", "payload" => text}, nil}
    end
  end

  defp error_messages(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", fn _placeholder -> error_value(value) end)
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, &"#{field_label(field)} #{&1}")
    end)
  end

  defp error_value(value) when is_binary(value) or is_number(value) or is_atom(value),
    do: to_string(value)

  defp error_value(value), do: inspect(value)

  defp field_label(:owner_type), do: "Owner"
  defp field_label(:owner_id), do: "Owner"
  defp field_label(:dedup), do: "Grouping:"
  defp field_label(:present), do: "Presentation:"
  defp field_label(:notify), do: "Notify:"
  defp field_label(:conditions), do: "Conditions:"
  defp field_label(field), do: field |> to_string() |> String.capitalize()

  defp field_paths(assigns) do
    test_paths = if assigns.test_env, do: Path.list(assigns.test_env), else: []
    Enum.uniq(test_paths ++ assigns.recent_paths) |> Enum.take(300)
  end

  defp results(%{test_env: nil}), do: %{}
  defp results(assigns), do: ConditionTree.evaluate(assigns.draft["conditions"], assigns.test_env)

  defp verdict(%{test_env: nil}), do: nil

  defp verdict(assigns) do
    tree = assigns.draft["conditions"]

    complete? =
      tree
      |> ConditionTree.leaves()
      |> Enum.all?(fn {_path, leaf} -> ConditionTree.complete_leaf?(leaf) end)

    complete? and Matcher.matches?(tree, assigns.test_env)
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        results: results(assigns),
        verdict: verdict(assigns),
        paths: field_paths(assigns)
      )

    ~H"""
    <Layouts.app flash={@flash} active={:rules}>
      <.link
        navigate={~p"/rules"}
        id="back-to-rules"
        class="inline-flex items-center gap-1 text-sm text-base-content/60 hover:text-base-content"
      >
        <.icon name="hero-arrow-left-mini" class="size-4" /> Rules
      </.link>

      <div class="flex flex-wrap items-end justify-between gap-4">
        <h1 class="text-2xl font-semibold tracking-tight">
          {if @rule.id, do: "Edit rule", else: "New rule"}
        </h1>
        <div class="join" role="group" aria-label="Editor mode">
          <button
            id="mode-visual"
            type="button"
            phx-click="mode"
            phx-value-mode="visual"
            class={["btn btn-sm join-item", @mode == "visual" && "btn-neutral"]}
          >
            Visual
          </button>
          <button
            id="mode-json"
            type="button"
            phx-click="mode"
            phx-value-mode="json"
            class={["btn btn-sm join-item", @mode == "json" && "btn-neutral"]}
          >
            JSON
          </button>
        </div>
      </div>

      <div
        :if={@errors != []}
        id="rule-errors"
        class="border border-base-content/20 bg-base-200 p-4 text-sm"
      >
        <p class="font-semibold">The rule can't be saved yet:</p>
        <ul class="mt-1 list-disc pl-5">
          <li :for={error <- @errors}>{error}</li>
        </ul>
      </div>

      <div class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <div :if={@mode == "json"}>
          <.form for={@form} id="json-form" phx-change="json_change" phx-submit="save">
            <p class="mb-2 text-sm text-base-content/60">
              The whole rule as JSON, in the same shape as the API and config files.
            </p>
            <textarea
              id="rule-json"
              name="json"
              rows="28"
              spellcheck="false"
              class="textarea w-full font-mono text-xs leading-relaxed"
            >{@json_text}</textarea>
            <p :if={@json_error} id="json-error" class="mt-2 text-sm font-medium">{@json_error}</p>
            <div class="mt-4 flex justify-end">
              <button id="save-rule" type="submit" class="btn btn-primary">Save rule</button>
            </div>
          </.form>
        </div>

        <.form
          :if={@mode == "visual"}
          for={@form}
          id="rule-form"
          phx-change="change"
          phx-submit="save"
          class="space-y-8"
        >
          <section class="grid gap-4 sm:grid-cols-2">
            <label class="block">
              <span class="mb-1 block text-xs font-semibold uppercase tracking-wide text-base-content/50">
                Name
              </span>
              <input
                id="rule-name"
                type="text"
                name="name"
                value={@draft["name"]}
                placeholder="e.g. Disk full"
                class="input w-full"
              />
            </label>
            <label class="block">
              <span class="mb-1 block text-xs font-semibold uppercase tracking-wide text-base-content/50">
                Owner
              </span>
              <select id="rule-owner" name="owner" class="select w-full">
                <option
                  :for={{label, value} <- @owner_options}
                  value={value}
                  selected={value == @draft["owner"]}
                >
                  {label}
                </option>
              </select>
            </label>
          </section>

          <section>
            <h2 class="mb-3 text-xs font-semibold uppercase tracking-wide text-base-content/50">
              When
            </h2>
            <.condition_group
              group={@draft["conditions"]}
              path={[]}
              results={@results}
              tested={not is_nil(@test_env)}
            />
            <datalist id="field-paths">
              <option :for={path <- @paths} value={path} />
            </datalist>
          </section>

          <section class="space-y-4">
            <h2 class="text-xs font-semibold uppercase tracking-wide text-base-content/50">Then</h2>
            <div class="flex flex-wrap items-center gap-2" id="rule-severity">
              <span class="text-sm">Raise a</span>
              <label
                :for={severity <- ~w(critical warning info)}
                class={[
                  "flex cursor-pointer items-center gap-2 border px-3 py-1.5 text-sm",
                  if(@draft["severity"] == severity,
                    do: "border-base-content bg-base-200 font-semibold",
                    else: "border-base-300"
                  )
                ]}
              >
                <input
                  type="radio"
                  name="severity"
                  value={severity}
                  checked={@draft["severity"] == severity}
                  class="sr-only"
                />
                <.rule_light severity={String.to_existing_atom(severity)} />
                {severity}
              </label>
              <span class="text-sm">alert</span>
            </div>
            <label class="block">
              <span class="mb-1 block text-sm">Titled</span>
              <input
                id="rule-title"
                type="text"
                name="title"
                value={@draft["title"]}
                placeholder="Disk full on {{payload.host}}"
                class="input w-full font-mono text-sm"
              />
            </label>
            <label class="block">
              <span class="mb-1 block text-sm">Body
              <span class="text-base-content/40">(optional)</span></span>
              <textarea
                id="rule-body"
                name="body"
                rows="2"
                placeholder="{{payload.host}} reported a full disk."
                class="textarea w-full font-mono text-sm"
              >{@draft["body"]}</textarea>
            </label>
            <div class="grid gap-4 sm:grid-cols-2">
              <label class="block">
                <span class="mb-1 block text-sm">Fields to show
                <span class="text-base-content/40">(comma-separated)</span></span>
                <input
                  id="rule-fields"
                  type="text"
                  name="fields"
                  value={@draft["fields"]}
                  list="field-paths"
                  placeholder="payload.host, payload.used"
                  class="input w-full font-mono text-sm"
                />
              </label>
              <label class="block">
                <span class="mb-1 block text-sm">Colour</span>
                <select id="rule-color" name="color" class="select w-full">
                  <option value="" selected={@draft["color"] == ""}>None</option>
                  <option
                    :for={color <- Draft.colors()}
                    value={color}
                    selected={@draft["color"] == color}
                  >
                    {color}
                  </option>
                </select>
              </label>
            </div>
          </section>

          <section class="space-y-3">
            <h2 class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
              Group repeats
            </h2>
            <div class="grid gap-4 sm:grid-cols-[minmax(0,1fr)_10rem]">
              <label class="block">
                <span class="mb-1 block text-sm">One alert per
                <span class="text-base-content/40">(fields, comma-separated; empty means one alert for the whole rule)</span></span>
                <input
                  id="rule-dedup-key"
                  type="text"
                  name="dedup_key"
                  value={@draft["dedup_key"]}
                  list="field-paths"
                  placeholder="payload.host"
                  class="input w-full font-mono text-sm"
                />
              </label>
              <label class="block">
                <span class="mb-1 block text-sm">Quiet after (min)</span>
                <input
                  id="rule-quiet"
                  type="number"
                  min="1"
                  name="quiet_min"
                  value={@draft["quiet_min"]}
                  class="input w-full"
                />
              </label>
            </div>
          </section>

          <section>
            <h2 class="mb-3 text-xs font-semibold uppercase tracking-wide text-base-content/50">
              Notify
            </h2>
            <input type="hidden" name="notify[]" value="" />
            <div id="rule-notify" class="grid gap-x-6 gap-y-2 sm:grid-cols-2">
              <label
                :for={option <- @notify_options}
                class="flex cursor-pointer items-center gap-2 text-sm"
              >
                <input
                  type="checkbox"
                  name="notify[]"
                  value={option.value}
                  checked={option.value in @draft["notify"]}
                  class="checkbox checkbox-sm"
                />
                {option.label}
              </label>
            </div>
            <p class="mt-2 text-xs text-base-content/50">
              Each person gets it on the channels they chose for this severity. Nobody ticked means the feed only.
            </p>
          </section>

          <div class="flex items-center justify-between gap-4 border-t border-base-300 pt-6">
            <label class="flex cursor-pointer items-center gap-2 text-sm">
              <input type="hidden" name="enabled" value="false" />
              <input
                id="rule-enabled"
                type="checkbox"
                name="enabled"
                value="true"
                checked={@draft["enabled"]}
                class="toggle toggle-sm"
              /> Enabled
            </label>
            <button id="save-rule" type="submit" class="btn btn-primary">Save rule</button>
          </div>
        </.form>

        <aside id="test-panel" class="space-y-3 lg:sticky lg:top-6 lg:self-start">
          <h2 class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
            Test against an event
          </h2>
          <.form for={@form} id="test-form" phx-change="test" class="space-y-2">
            <select id="test-recent" name="recent" class="select select-sm w-full">
              <option value="">Pick the event of a recent alert…</option>
              <option :for={{label, id} <- @recent_events} value={id} selected={id == @recent_choice}>
                {label}
              </option>
            </select>
            <textarea
              id="test-event"
              name="event"
              rows="12"
              spellcheck="false"
              phx-debounce="200"
              placeholder={~s({"type": "DISK_FULL", "host": "web-1"})}
              class="textarea w-full font-mono text-xs"
            >{@test_text}</textarea>
          </.form>
          <p class="text-xs text-base-content/50">
            Paste a raw payload or a full envelope. Field paths from it are suggested in the editor.
          </p>

          <div :if={is_nil(@test_env)} class="text-sm text-base-content/50">
            Paste an event to see, as you edit, which conditions it meets.
          </div>
          <div
            :if={@test_env}
            id="test-result"
            data-matches={to_string(@verdict)}
            class="space-y-2 border-t border-base-300 pt-3 text-sm"
          >
            <p class="flex items-center gap-2 font-semibold">
              <.icon
                name={if @verdict, do: "hero-check-circle", else: "hero-x-circle"}
                class={["size-5", if(@verdict, do: "text-success", else: "text-base-content/40")]}
              />
              {if @verdict, do: "This rule matches", else: "This rule does not match"}
            </p>
            <div :if={@verdict}>
              <p class="text-xs uppercase tracking-wide text-base-content/50">The alert would read</p>
              <p id="test-title" class="font-medium">
                {Template.render(@draft["title"], @test_env) |> blank_to(@draft["name"])}
              </p>
              <p :if={@draft["body"] != ""} class="text-base-content/70">
                {Template.render(@draft["body"], @test_env)}
              </p>
            </div>
          </div>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  defp blank_to(text, fallback), do: if(String.trim(text) == "", do: fallback, else: text)

  attr :group, :map, required: true
  attr :path, :list, required: true
  attr :results, :map, required: true
  attr :tested, :boolean, required: true

  defp condition_group(assigns) do
    assigns = assign(assigns, :id, ConditionTree.path_id(assigns.path))

    ~H"""
    <div
      id={"group-#{@id}"}
      class={["space-y-2", @path != [] && "border-l-2 border-base-300 py-1 pl-4"]}
    >
      <div class="flex items-center gap-2 text-sm">
        <span>{if @path == [], do: "An event matches when", else: "and"}</span>
        <select name={"g[#{@id}]"} class="select select-sm w-auto">
          <option value="all" selected={ConditionTree.mode(@group) == "all"}>all</option>
          <option value="any" selected={ConditionTree.mode(@group) == "any"}>any</option>
        </select>
        <span>of these are true:</span>
        <button
          :if={@path != []}
          type="button"
          phx-click="remove"
          phx-value-path={@id}
          class="btn btn-ghost btn-xs ml-auto"
          aria-label="Remove group"
        >
          <.icon name="hero-x-mark-mini" class="size-4" />
        </button>
      </div>

      <div :for={{child, index} <- Enum.with_index(ConditionTree.children(@group))}>
        <.condition_group
          :if={ConditionTree.group?(child)}
          group={child}
          path={@path ++ [index]}
          results={@results}
          tested={@tested}
        />
        <.condition_row
          :if={not ConditionTree.group?(child)}
          leaf={child}
          path={@path ++ [index]}
          result={Map.get(@results, @path ++ [index])}
          tested={@tested}
        />
      </div>

      <div class="flex gap-2 pt-1">
        <button
          type="button"
          id={"add-condition-#{@id}"}
          phx-click="add_condition"
          phx-value-path={@id}
          class="btn btn-ghost btn-xs"
        >
          <.icon name="hero-plus-mini" class="size-4" /> condition
        </button>
        <button
          :if={@path == []}
          type="button"
          id="add-group"
          phx-click="add_group"
          class="btn btn-ghost btn-xs"
        >
          <.icon name="hero-plus-mini" class="size-4" /> group
        </button>
      </div>
    </div>
    """
  end

  attr :leaf, :map, required: true
  attr :path, :list, required: true
  attr :result, :any, default: nil
  attr :tested, :boolean, required: true

  defp condition_row(assigns) do
    assigns = assign(assigns, :id, ConditionTree.path_id(assigns.path))

    ~H"""
    <div
      id={"condition-#{@id}"}
      class="flex flex-wrap items-center gap-2"
      data-result={to_string(@result)}
    >
      <input
        type="text"
        name={"c[#{@id}][field]"}
        value={@leaf["field"]}
        list="field-paths"
        placeholder="payload.type"
        aria-label="Field"
        class="input input-sm w-56 font-mono"
      />
      <select name={"c[#{@id}][op]"} aria-label="Operator" class="select select-sm w-36">
        <option :for={op <- ConditionTree.ops()} value={op} selected={op == @leaf["op"]}>
          {ConditionTree.op_label(op)}
        </option>
      </select>
      <input
        type="text"
        name={"c[#{@id}][value]"}
        value={ConditionTree.value_text(@leaf)}
        placeholder={value_placeholder(@leaf["op"])}
        disabled={@leaf["op"] == "exists"}
        aria-label="Value"
        class="input input-sm min-w-32 flex-1 font-mono"
      />
      <span class="inline-flex w-5 justify-center">
        <.icon
          :if={@tested and @result == true}
          name="hero-check-mini"
          class="size-5 text-success"
        />
        <.icon
          :if={@tested and @result == false}
          name="hero-x-mark-mini"
          class="size-5 text-base-content/40"
        />
      </span>
      <button
        type="button"
        phx-click="remove"
        phx-value-path={@id}
        class="btn btn-ghost btn-xs"
        aria-label="Remove condition"
      >
        <.icon name="hero-trash-mini" class="size-4 text-base-content/50" />
      </button>
    </div>
    """
  end

  defp value_placeholder("in"), do: "a, b, c"
  defp value_placeholder("exists"), do: "no value needed"
  defp value_placeholder("matches"), do: "pricing-engine-*"
  defp value_placeholder(_op), do: "value"
end
