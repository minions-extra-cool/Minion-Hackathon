defmodule MinionWeb.AlertComponents do
  use Phoenix.Component
  use MinionWeb, :verified_routes

  import MinionWeb.CoreComponents, only: [icon: 1]

  alias Minion.Alerts.Alert

  attr :status, :atom, required: true
  attr :severity, :atom, required: true
  attr :closed, :boolean, default: false
  attr :id, :string, default: nil

  def status_light(assigns) do
    assigns =
      assign(assigns, :label, light_label(assigns.status, assigns.severity, assigns.closed))

    ~H"""
    <span
      id={@id}
      class="inline-flex size-3 items-center justify-center"
      title={@label}
      data-status={@status}
      data-severity={@severity}
    >
      <span class={[
        "status-light",
        @status == :open && "status-light-open",
        @status == :acked && "status-light-acked",
        @status == :resolved && "status-light-resolved",
        @severity == :critical && "status-light-critical",
        @severity == :warning && "status-light-warning",
        @severity == :info && "status-light-info"
      ]} />
      <span class="sr-only">{@label}</span>
    </span>
    """
  end

  defp light_label(:resolved, severity, _closed), do: "Resolved, #{severity}"
  defp light_label(status, severity, closed), do: "#{status_label(status, closed)}, #{severity}"

  attr :severity, :atom, required: true
  attr :enabled, :boolean, default: true

  def rule_light(assigns) do
    ~H"""
    <span
      class="inline-flex size-3 items-center justify-center"
      title={"#{@severity}#{if @enabled, do: "", else: ", disabled"}"}
      data-severity={@severity}
      data-enabled={to_string(@enabled)}
    >
      <span class={[
        "status-light",
        if(@enabled, do: "status-light-open", else: "status-light-resolved"),
        @severity == :critical && "status-light-critical",
        @severity == :warning && "status-light-warning",
        @severity == :info && "status-light-info"
      ]} />
    </span>
    """
  end

  attr :active, :atom, required: true, values: [:alerts, :unmatched]
  slot :actions

  def feed_header(assigns) do
    ~H"""
    <div class="flex min-h-8 flex-wrap items-center justify-between gap-4 [&_.fieldset]:mb-0 [&_.fieldset]:py-0">
      <h1 class="text-2xl font-semibold tracking-tight">Live feed</h1>
      {render_slot(@actions)}
    </div>

    <nav id="feed-tabs" class="flex gap-6 border-b border-base-300 text-sm" aria-label="Feed">
      <.feed_tab id="tab-alerts" navigate={~p"/"} label="Alerts" active={@active == :alerts} />
      <.feed_tab
        id="tab-unmatched"
        navigate={~p"/unmatched"}
        label="Unmatched events"
        active={@active == :unmatched}
      />
    </nav>
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, required: true

  defp feed_tab(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      data-label={@label}
      class={[
        "-mb-px inline-flex flex-col border-b-2 pb-2 transition-colors",
        "after:invisible after:h-0 after:overflow-hidden after:font-semibold after:content-[attr(data-label)]",
        if(@active,
          do: "border-base-content font-semibold",
          else: "border-transparent text-base-content/60 hover:text-base-content"
        )
      ]}
    >
      {@label}
    </.link>
    """
  end

  def status_label(:open, false), do: "Open"
  def status_label(:open, true), do: "Open, no new events (quiet)"
  def status_label(:acked, false), do: "Acknowledged"
  def status_label(:acked, true), do: "Acknowledged, no new events (quiet)"
  def status_label(:resolved, _closed), do: "Resolved"

  attr :severity, :atom, required: true

  def severity_badge(%{severity: :critical} = assigns) do
    ~H"""
    <span class="badge badge-sm gap-1 border-0 bg-base-content font-semibold text-base-100">
      <.icon name="hero-exclamation-triangle-micro" class="size-3" /> critical
    </span>
    """
  end

  def severity_badge(%{severity: :warning} = assigns) do
    ~H"""
    <span class="badge badge-sm border-base-content/35 bg-transparent font-medium text-base-content/80">
      warning
    </span>
    """
  end

  def severity_badge(assigns) do
    ~H"""
    <span class="px-1 text-xs font-medium text-base-content/50">{@severity}</span>
    """
  end

  attr :alert, Alert, required: true

  def rule_color_swatch(assigns) do
    assigns = assign(assigns, :color, rule_color(assigns.alert))

    ~H"""
    <span :if={@color} class="inline-flex items-center gap-1.5 text-base-content/60">
      <span class={["inline-block size-2.5", swatch_class(@color)]} />
      {@color}
    </span>
    """
  end

  defp rule_color(%Alert{rule: %{present: %{"color" => color}}}) when is_binary(color),
    do: String.downcase(color)

  defp rule_color(_alert), do: nil

  defp swatch_class("red"), do: "bg-error"
  defp swatch_class(color) when color in ["amber", "orange", "yellow"], do: "bg-warning"
  defp swatch_class("green"), do: "bg-success"
  defp swatch_class("blue"), do: "bg-info"
  defp swatch_class(_other), do: "bg-base-content/30"

  attr :id, :string, required: true
  attr :at, DateTime, required: true
  attr :format, :string, default: "relative", values: ~w(relative absolute)

  def local_time(assigns) do
    ~H"""
    <time
      id={@id}
      phx-hook=".LocalTime"
      datetime={DateTime.to_iso8601(@at)}
      data-format={@format}
      class="tabular-nums"
    >
      <span id={"#{@id}-text"} phx-update="ignore">{Calendar.strftime(@at, "%Y-%m-%d %H:%M:%S UTC")}</span>
    </time>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".LocalTime">
      const relative = (date) => {
        const seconds = Math.round((Date.now() - date.getTime()) / 1000)
        if (seconds < 10) return "just now"
        if (seconds < 60) return `${seconds}s ago`
        if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`
        if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`
        return date.toLocaleString([], {month: "short", day: "numeric", hour: "2-digit", minute: "2-digit"})
      }

      const absolute = (date) =>
        date.toLocaleString([], {dateStyle: "medium", timeStyle: "medium"})

      export default {
        mounted() {
          this.render()
          this.timer = setInterval(() => this.render(), 15000)
        },
        updated() { this.render() },
        destroyed() { clearInterval(this.timer) },
        render() {
          const date = new Date(this.el.getAttribute("datetime"))
          const format = this.el.dataset.format === "absolute" ? absolute : relative
          this.el.firstElementChild.textContent = format(date)
          this.el.title = date.toLocaleString([], {dateStyle: "full", timeStyle: "long"})
        }
      }
    </script>
    """
  end

  def source(%Alert{sample_event: %{"source" => source}}) when is_binary(source), do: source
  def source(_alert), do: "unknown"

  def source_type(%Alert{sample_event: %{"source_type" => type}}) when is_binary(type), do: type
  def source_type(_alert), do: nil
end
