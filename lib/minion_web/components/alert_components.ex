defmodule MinionWeb.AlertComponents do
  use Phoenix.Component

  alias Minion.Alerts.Alert

  attr :status, :atom, required: true
  attr :closed, :boolean, default: false
  attr :id, :string, default: nil

  def status_light(assigns) do
    assigns = assign(assigns, :label, status_label(assigns.status, assigns.closed))

    ~H"""
    <span id={@id} class="inline-flex items-center" title={@label} data-status={@status}>
      <span class={[
        "inline-block size-3 rounded-full",
        @status == :open && "bg-error ring-4 ring-error/20",
        @status == :acked && "bg-warning ring-4 ring-warning/25",
        @status == :resolved && "bg-base-content/25"
      ]} />
      <span class="sr-only">{@label}</span>
    </span>
    """
  end

  def status_label(:open, false), do: "Open"
  def status_label(:open, true), do: "Open, no new events (quiet)"
  def status_label(:acked, false), do: "Acknowledged"
  def status_label(:acked, true), do: "Acknowledged, no new events (quiet)"
  def status_label(:resolved, _closed), do: "Resolved"

  attr :severity, :atom, required: true

  def severity_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm font-medium",
      @severity == :critical && "badge-error badge-soft",
      @severity == :warning && "badge-warning badge-soft",
      @severity == :info && "badge-ghost"
    ]}>
      {@severity}
    </span>
    """
  end

  attr :alert, Alert, required: true
  attr :class, :any, default: nil

  def rule_stripe(assigns) do
    assigns = assign(assigns, :color, rule_color(assigns.alert))

    ~H"""
    <span
      class={["inline-block w-1 rounded-full", stripe_class(@color), @class]}
      title={@color && "Rule colour: #{@color}"}
    />
    """
  end

  defp rule_color(%Alert{rule: %{present: %{"color" => color}}}) when is_binary(color),
    do: String.downcase(color)

  defp rule_color(_alert), do: nil

  defp stripe_class("red"), do: "bg-error"
  defp stripe_class(color) when color in ["amber", "orange", "yellow"], do: "bg-warning"
  defp stripe_class("green"), do: "bg-success"
  defp stripe_class("blue"), do: "bg-info"
  defp stripe_class(color) when color in ["gray", "grey"], do: "bg-base-content/30"
  defp stripe_class(_none), do: "bg-transparent"

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
