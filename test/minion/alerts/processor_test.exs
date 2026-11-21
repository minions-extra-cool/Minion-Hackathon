defmodule Minion.Alerts.ProcessorTest do
  use Minion.DataCase, async: true

  alias Minion.Alerts
  alias Minion.Alerts.{Alert, Processor}
  alias Minion.Rules.Rule

  defp insert_rule(attrs \\ %{}) do
    Repo.insert!(
      struct(
        %Rule{
          name: "Disk full",
          owner_type: :team,
          owner_id: Ecto.UUID.generate(),
          severity: :warning,
          conditions: %{"field" => "payload.type", "op" => "eq", "value" => "DISK_FULL"},
          dedup: %{"key" => ["payload.host"]},
          present: %{
            "title" => "Disk full on {{payload.host}}",
            "body" => "{{payload.used}}% used"
          },
          notify: []
        },
        attrs
      )
    )
  end

  defp event(payload), do: Minion.Ingest.envelope("test", "http", payload)

  defp recording_dispatch do
    test_pid = self()

    fn alert ->
      send(test_pid, {:dispatched, alert.id})
      :ok
    end
  end

  defp alerts, do: Repo.all(from a in Alert, order_by: [desc: a.count])

  test "the five-event DISK_FULL example creates two alerts and notifies twice" do
    rule = insert_rule()

    for payload <- [
          %{"type" => "DISK_FULL", "host" => "web-1"},
          %{"type" => "DISK_FULL", "host" => "web-1"},
          %{"type" => "CPU_HIGH", "host" => "web-1"},
          %{"type" => "DISK_FULL", "host" => "web-2"},
          %{"type" => "DISK_FULL", "host" => "web-1"}
        ] do
      assert {:ok, _} = Processor.process(event(payload), [rule], dispatch: recording_dispatch())
    end

    assert [
             %Alert{title: "Disk full on web-1", count: 3},
             %Alert{title: "Disk full on web-2", count: 1}
           ] =
             alerts()

    assert_received {:dispatched, _}
    assert_received {:dispatched, _}
    refute_received {:dispatched, _}
  end

  test "a new alert is built from the rule and the first event" do
    rule = insert_rule()
    first = event(%{"type" => "DISK_FULL", "host" => "web-1", "used" => 97})

    {:ok, [{:created, alert}]} = Processor.process(first, [rule], dispatch: recording_dispatch())

    assert %Alert{
             status: :open,
             severity: :warning,
             count: 1,
             title: "Disk full on web-1",
             body: "97% used",
             owner_type: :team
           } = alert

    assert alert.rule_id == rule.id
    assert alert.owner_id == rule.owner_id
    assert alert.sample_event == first
    assert alert.first_seen == alert.last_seen
  end

  test "a repeat increments the count and last_seen without notifying again" do
    rule = insert_rule()
    payload = %{"type" => "DISK_FULL", "host" => "web-1"}

    {:ok, [{:created, created}]} =
      Processor.process(event(payload), [rule], dispatch: recording_dispatch())

    assert_received {:dispatched, _}

    {:ok, [{:updated, updated}]} =
      Processor.process(event(payload), [rule], dispatch: recording_dispatch())

    refute_received {:dispatched, _}
    assert updated.id == created.id
    assert updated.count == 2
    assert DateTime.compare(updated.last_seen, created.last_seen) == :gt
  end

  test "an event after the alert is resolved opens a new alert" do
    rule = insert_rule()
    payload = %{"type" => "DISK_FULL", "host" => "web-1"}

    {:ok, [{:created, first}]} =
      Processor.process(event(payload), [rule], dispatch: recording_dispatch())

    first |> Ecto.Changeset.change(status: :resolved) |> Repo.update!()

    {:ok, [{:created, second}]} =
      Processor.process(event(payload), [rule], dispatch: recording_dispatch())

    refute second.id == first.id
  end

  test "an event matching two rules creates an alert for each" do
    disk = insert_rule()

    web1 =
      insert_rule(%{
        name: "Anything on web-1",
        conditions: %{"field" => "payload.host", "op" => "eq", "value" => "web-1"},
        present: %{}
      })

    {:ok, outcomes} =
      Processor.process(event(%{"type" => "DISK_FULL", "host" => "web-1"}), [disk, web1],
        dispatch: recording_dispatch()
      )

    assert outcomes |> Enum.map(fn {event, alert} -> {event, alert.title} end) |> Enum.sort() ==
             [{:created, "Anything on web-1"}, {:created, "Disk full on web-1"}]
  end

  test "an event matching no rule changes nothing" do
    rule = insert_rule()

    assert {:ok, []} =
             Processor.process(event(%{"type" => "CPU_HIGH"}), [rule],
               dispatch: recording_dispatch()
             )

    assert alerts() == []
    refute_received {:dispatched, _}
  end

  test "an event matching no rule is recorded as an unmatched shape" do
    rule = insert_rule()

    Processor.process(event(%{"type" => "CPU_HIGH"}), [rule], dispatch: recording_dispatch())

    assert [%Minion.Unmatched.Shape{source: "test", count: 1}] =
             Repo.all(Minion.Unmatched.Shape)
  end

  test "subscribers are told about created and updated alerts" do
    rule = insert_rule()
    payload = %{"type" => "DISK_FULL", "host" => "web-1"}
    Phoenix.PubSub.subscribe(Minion.PubSub, "alerts:team:#{rule.owner_id}")

    {:ok, [{:created, alert}]} =
      Processor.process(event(payload), [rule], dispatch: recording_dispatch())

    assert Alerts.topic(alert) == "alerts:team:#{rule.owner_id}"
    assert_received {:alert, :created, %Alert{count: 1}}

    Processor.process(event(payload), [rule], dispatch: recording_dispatch())
    assert_received {:alert, :updated, %Alert{count: 2}}
  end

  describe "process_batch/2" do
    defp batch(rule, payloads),
      do: Enum.flat_map(payloads, &Processor.candidates(event(&1), [rule]))

    test "folds a batch of repeats into one row per alert and notifies once per new alert" do
      rule = insert_rule()

      payloads =
        List.duplicate(%{"type" => "DISK_FULL", "host" => "web-1"}, 5) ++
          [
            %{"type" => "DISK_FULL", "host" => "web-2"},
            %{"type" => "CPU_HIGH", "host" => "web-3"}
          ]

      {:ok, outcomes} =
        Processor.process_batch(batch(rule, payloads), dispatch: recording_dispatch())

      assert outcomes
             |> Enum.map(fn {event, alert} -> {event, alert.title, alert.count} end)
             |> Enum.sort() ==
               [{:created, "Disk full on web-1", 5}, {:created, "Disk full on web-2", 1}]

      assert_received {:dispatched, _}
      assert_received {:dispatched, _}
      refute_received {:dispatched, _}
    end

    test "adds a batch's events to an open alert without notifying again" do
      rule = insert_rule()
      payload = %{"type" => "DISK_FULL", "host" => "web-1"}

      {:ok, [{:created, existing}]} =
        Processor.process(event(payload), [rule], dispatch: recording_dispatch())

      assert_received {:dispatched, _}

      {:ok, [{:updated, updated}]} =
        Processor.process_batch(batch(rule, List.duplicate(payload, 4)),
          dispatch: recording_dispatch()
        )

      refute_received {:dispatched, _}
      assert updated.id == existing.id
      assert updated.count == 5
      assert DateTime.compare(updated.last_seen, existing.last_seen) == :gt
    end

    test "creates and updates in the same batch" do
      rule = insert_rule()

      {:ok, _} =
        Processor.process(event(%{"type" => "DISK_FULL", "host" => "old"}), [rule],
          dispatch: recording_dispatch()
        )

      {:ok, outcomes} =
        Processor.process_batch(
          batch(rule, [
            %{"type" => "DISK_FULL", "host" => "old"},
            %{"type" => "DISK_FULL", "host" => "new"}
          ]),
          dispatch: recording_dispatch()
        )

      assert outcomes |> Enum.map(fn {event, alert} -> {event, alert.title} end) |> Enum.sort() ==
               [{:created, "Disk full on new"}, {:updated, "Disk full on old"}]
    end

    test "if dispatch fails for one new alert, the whole batch is rolled back" do
      rule = insert_rule()

      payloads = [
        %{"type" => "DISK_FULL", "host" => "a"},
        %{"type" => "DISK_FULL", "host" => "b"}
      ]

      fail_for_b = fn alert -> if alert.title =~ "on b", do: {:error, :boom}, else: :ok end

      assert {:error, {:dispatch_failed, :boom}} =
               Processor.process_batch(batch(rule, payloads), dispatch: fail_for_b)

      assert alerts() == []
    end
  end

  describe "the transaction rule" do
    test "if dispatch raises, no alert row is left behind" do
      rule = insert_rule()

      assert_raise RuntimeError, "delivery is down", fn ->
        Processor.process(event(%{"type" => "DISK_FULL", "host" => "web-1"}), [rule],
          dispatch: fn _alert -> raise "delivery is down" end
        )
      end

      assert alerts() == []
    end

    test "if dispatch returns an error, no alert row is left and nothing is broadcast" do
      rule = insert_rule()
      Phoenix.PubSub.subscribe(Minion.PubSub, "alerts:team:#{rule.owner_id}")

      assert {:error, {:dispatch_failed, :no_recipients}} =
               Processor.process(event(%{"type" => "DISK_FULL", "host" => "web-1"}), [rule],
                 dispatch: fn _alert -> {:error, :no_recipients} end
               )

      assert alerts() == []
      refute_received {:alert, _, _}
    end

    test "a failure on the second matching rule rolls back the first rule's alert too" do
      disk = insert_rule()

      web1 =
        insert_rule(%{
          name: "Anything on web-1",
          conditions: %{"field" => "payload.host", "op" => "eq", "value" => "web-1"}
        })

      failing_for_web1 = fn alert ->
        if alert.rule_id == web1.id, do: {:error, :boom}, else: :ok
      end

      assert {:error, _} =
               Processor.process(event(%{"type" => "DISK_FULL", "host" => "web-1"}), [disk, web1],
                 dispatch: failing_for_web1
               )

      assert alerts() == []
    end
  end
end
