defmodule Minion.Rules.FingerprintTest do
  use ExUnit.Case, async: true

  alias Minion.Rules.{Fingerprint, Matcher}

  @disk_full %{
    id: "rule-disk-full",
    conditions: %{"field" => "payload.type", "op" => "eq", "value" => "DISK_FULL"},
    dedup: %{"key" => ["payload.host"]}
  }

  defp event(payload), do: %{"source" => "test", "payload" => payload}

  test "events with the same key values share a fingerprint" do
    first = event(%{"type" => "DISK_FULL", "host" => "web-1", "used" => 97})
    second = event(%{"type" => "DISK_FULL", "host" => "web-1", "used" => 99})

    assert Fingerprint.compute(@disk_full, first) == Fingerprint.compute(@disk_full, second)
  end

  test "different key values, or a different rule, give a different fingerprint" do
    web1 = event(%{"host" => "web-1"})
    web2 = event(%{"host" => "web-2"})

    refute Fingerprint.compute(@disk_full, web1) == Fingerprint.compute(@disk_full, web2)

    refute Fingerprint.compute(@disk_full, web1) ==
             Fingerprint.compute(%{@disk_full | id: "other-rule"}, web1)
  end

  test "with no dedup key, every event of the rule shares one fingerprint" do
    rule = %{@disk_full | dedup: %{}}

    assert Fingerprint.compute(rule, event(%{"host" => "web-1"})) ==
             Fingerprint.compute(rule, event(%{"host" => "web-2"}))
  end

  test "the five-event DISK_FULL example gives two alerts with counts 3 and 1" do
    events =
      Enum.map(
        [
          %{"type" => "DISK_FULL", "host" => "web-1"},
          %{"type" => "DISK_FULL", "host" => "web-1"},
          %{"type" => "CPU_HIGH", "host" => "web-1"},
          %{"type" => "DISK_FULL", "host" => "web-2"},
          %{"type" => "DISK_FULL", "host" => "web-1"}
        ],
        &event/1
      )

    counts =
      events
      |> Enum.filter(&Matcher.matches?(@disk_full.conditions, &1))
      |> Enum.frequencies_by(&Fingerprint.compute(@disk_full, &1))
      |> Map.values()
      |> Enum.sort(:desc)

    assert counts == [3, 1]
  end
end
