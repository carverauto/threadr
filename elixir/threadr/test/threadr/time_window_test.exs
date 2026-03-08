defmodule Threadr.TimeWindowTest do
  use ExUnit.Case, async: true

  alias Threadr.TimeWindow

  test "builds baseline and comparison windows from opts" do
    opts = [
      since: ~N[2026-03-05 11:30:00],
      until: ~N[2026-03-05 12:30:00],
      compare_since: ~N[2026-03-05 12:30:00],
      compare_until: ~N[2026-03-05 13:30:00]
    ]

    baseline = TimeWindow.from_opts(opts)
    comparison = TimeWindow.from_opts(opts, :compare)

    assert TimeWindow.to_map(baseline) == %{
             since: ~N[2026-03-05 11:30:00],
             until: ~N[2026-03-05 12:30:00]
           }

    assert TimeWindow.to_keyword(comparison) == [
             since: ~N[2026-03-05 12:30:00],
             until: ~N[2026-03-05 13:30:00]
           ]
  end
end
