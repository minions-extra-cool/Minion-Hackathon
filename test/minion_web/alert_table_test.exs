defmodule MinionWeb.AlertTableTest do
  use ExUnit.Case, async: true

  alias Minion.Alerts.Alert
  alias MinionWeb.AlertTable

  defp alert(id, attrs) do
    struct(
      %Alert{
        id: id,
        title: "t",
        severity: :warning,
        status: :open,
        count: 1,
        owner_type: :team,
        owner_id: "o",
        first_seen: ~U[2026-11-21 10:00:00Z],
        last_seen: ~U[2026-11-21 10:00:00Z],
        sample_event: %{"source" => "s"}
      },
      attrs
    )
  end

  defp ids(alerts), do: Enum.map(alerts, & &1.id)

  describe "layout" do
    test "unknown and repeated columns are dropped and the title always stays" do
      assert AlertTable.normalize_layout(["owner", "nope", "owner"]) == ["title", "owner"]
      assert AlertTable.normalize_layout("garbage") == AlertTable.default_layout()
    end

    test "toggling shows or hides a column, but never the title" do
      layout = ["title", "owner"]
      assert AlertTable.toggle(layout, "owner") == ["title"]
      assert AlertTable.toggle(layout, "rule") == ["title", "owner", "rule"]
      assert AlertTable.toggle(layout, "title") == layout
      assert AlertTable.toggle(layout, "nope") == layout
    end

    test "moving stops at the ends" do
      layout = ["title", "owner", "count"]
      assert AlertTable.move(layout, "count", :up) == ["title", "count", "owner"]
      assert AlertTable.move(layout, "title", :up) == layout
      assert AlertTable.move(layout, "count", :down) == layout
    end
  end

  describe "sort" do
    test "parsing falls back to newest first and picks a sensible first direction" do
      assert AlertTable.parse_sort(%{}) == {"last_seen", :desc}
      assert AlertTable.parse_sort(%{"sort" => "title"}) == {"title", :asc}
      assert AlertTable.parse_sort(%{"sort" => "count", "dir" => "asc"}) == {"count", :asc}
      assert AlertTable.parse_sort(%{"sort" => "drop table"}) == {"last_seen", :desc}
    end

    test "clicking the same column flips it, another column starts fresh" do
      assert AlertTable.next_sort({"title", :asc}, "title") == {"title", :desc}
      assert AlertTable.next_sort({"title", :desc}, "count") == {"count", :desc}
      assert AlertTable.next_sort({"count", :desc}, "owner") == {"owner", :asc}
    end

    test "sorts by text ignoring case, by numbers, and by severity then state" do
      a = alert("a", title: "beta", count: 5, severity: :info)
      b = alert("b", title: "Alpha", count: 50, severity: :critical, status: :resolved)
      c = alert("c", title: "gamma", count: 7, severity: :critical)

      assert ids(AlertTable.sort([a, b, c], {"title", :asc}, %{})) == ~w(b a c)
      assert ids(AlertTable.sort([a, b, c], {"count", :desc}, %{})) == ~w(b c a)
      assert ids(AlertTable.sort([a, b, c], {"light", :desc}, %{})) == ~w(c b a)
    end

    test "sorts owners by name and breaks ties with the newest event" do
      owners = %{{:team, "x"} => "zeta", {:team, "y"} => "Ops"}
      older = alert("old", owner_id: "y", last_seen: ~U[2026-11-21 09:00:00Z])
      newer = alert("new", owner_id: "y", last_seen: ~U[2026-11-21 11:00:00Z])
      other = alert("z", owner_id: "x")

      assert ids(AlertTable.sort([other, older, newer], {"owner", :asc}, owners)) ==
               ~w(new old z)
    end
  end
end
