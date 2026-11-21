defmodule Minion.FuzzyTest do
  use ExUnit.Case, async: true

  alias Minion.Fuzzy

  test "an empty query matches everything" do
    assert Fuzzy.match?("", "Disk full on web-3")
    assert Fuzzy.match?(nil, "Disk full on web-3")
  end

  test "letters must appear in order within one word, with gaps allowed" do
    assert Fuzzy.match?("dsk", "Disk full on web-3")
    assert Fuzzy.match?("web3", "Disk full on web-3")
    assert Fuzzy.match?("papi", "High error rate on payments-api (eu-west)")
    refute Fuzzy.match?("ksd", "Disk full on web-3")
    refute Fuzzy.match?("db", "Disk full on web-3")
  end

  test "every word must match, anywhere in the text" do
    assert Fuzzy.match?("web3 disk", "Disk full on web-3")
    refute Fuzzy.match?("disk db", "Disk full on web-3")
  end

  test "ignores case and accents" do
    assert Fuzzy.match?("PAYMENTS", "Payments down in us-east")
    assert Fuzzy.match?("lukasz", "Łukasz")
    assert Fuzzy.match?("zolw", "Żółw")
  end

  test "a query longer than the text does not match" do
    refute Fuzzy.match?("disk full on web-3 now", "Disk full on web-3")
  end
end
