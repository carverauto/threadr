defmodule Threadr.CompareDelta do
  @moduledoc """
  Shared comparison helpers for extracted entities and facts across temporal windows.
  """

  def build(baseline_entities, comparison_entities, baseline_facts, comparison_facts) do
    %{
      entity_delta: entity_delta(baseline_entities, comparison_entities),
      fact_delta: fact_delta(baseline_facts, comparison_facts)
    }
  end

  def entity_delta(baseline, comparison) do
    baseline_counts = count_by_signature(baseline, &entity_signature/1)
    comparison_counts = count_by_signature(comparison, &entity_signature/1)

    added =
      delta_entries(comparison_counts, baseline_counts, :positive)
      |> Enum.map(&decorate_entity_entry/1)

    removed =
      delta_entries(baseline_counts, comparison_counts, :positive)
      |> Enum.map(&decorate_entity_entry/1)

    %{
      baseline_count: Enum.sum(Map.values(baseline_counts)),
      comparison_count: Enum.sum(Map.values(comparison_counts)),
      added: added,
      removed: removed,
      unchanged: overlap_count(baseline_counts, comparison_counts),
      added_by_type: group_entity_entries(added),
      removed_by_type: group_entity_entries(removed),
      highlights: %{
        new_people: filter_entity_entries(added, "person"),
        removed_people: filter_entity_entries(removed, "person"),
        new_topics: filter_entity_entries(added, "topic"),
        removed_topics: filter_entity_entries(removed, "topic")
      }
    }
  end

  def fact_delta(baseline, comparison) do
    baseline_counts = count_by_signature(baseline, &fact_signature/1)
    comparison_counts = count_by_signature(comparison, &fact_signature/1)

    added =
      delta_entries(comparison_counts, baseline_counts, :positive)
      |> Enum.map(&decorate_fact_entry/1)

    removed =
      delta_entries(baseline_counts, comparison_counts, :positive)
      |> Enum.map(&decorate_fact_entry/1)

    %{
      baseline_count: Enum.sum(Map.values(baseline_counts)),
      comparison_count: Enum.sum(Map.values(comparison_counts)),
      added: added,
      removed: removed,
      unchanged: overlap_count(baseline_counts, comparison_counts),
      added_by_subject: group_fact_entries(added),
      removed_by_subject: group_fact_entries(removed),
      highlights: %{
        new_claims: added,
        dropped_claims: removed
      }
    }
  end

  defp count_by_signature(items, signature_fun) do
    items
    |> Enum.map(signature_fun)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.frequencies()
  end

  defp delta_entries(left_counts, right_counts, direction) do
    left_counts
    |> Enum.map(fn {label, count} ->
      diff = count - Map.get(right_counts, label, 0)
      {label, diff}
    end)
    |> Enum.filter(fn {_label, diff} ->
      case direction do
        :positive -> diff > 0
      end
    end)
    |> Enum.map(fn {label, diff} ->
      %{label: label, count: abs(diff)}
    end)
    |> Enum.sort_by(fn %{count: count, label: label} -> {-count, label} end)
  end

  defp overlap_count(left_counts, right_counts) do
    left_counts
    |> Enum.reduce(0, fn {label, count}, acc ->
      acc + min(count, Map.get(right_counts, label, 0))
    end)
  end

  defp entity_signature(entity) do
    entity_type = field(entity, :entity_type)
    name = field(entity, :canonical_name) || field(entity, :name)

    [entity_type, name]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(": ")
  end

  defp fact_signature(fact) do
    [field(fact, :subject), field(fact, :predicate), field(fact, :object)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp group_entity_entries(entries) do
    entries
    |> Enum.group_by(&(&1[:entity_type] || entity_type_from_label(&1.label)))
    |> Enum.map(fn {type, grouped} ->
      %{type: type, count: Enum.sum(Enum.map(grouped, & &1.count))}
    end)
    |> Enum.sort_by(fn %{count: count, type: type} -> {-count, type} end)
  end

  defp filter_entity_entries(entries, type) do
    Enum.filter(entries, &((&1[:entity_type] || entity_type_from_label(&1.label)) == type))
  end

  defp entity_type_from_label(label) when is_binary(label) do
    case String.split(label, ": ", parts: 2) do
      [type, _rest] -> type
      _ -> "unknown"
    end
  end

  defp group_fact_entries(entries) do
    entries
    |> Enum.group_by(&(&1[:subject] || fact_subject_from_label(&1.label)))
    |> Enum.map(fn {subject, grouped} ->
      %{subject: subject, count: Enum.sum(Enum.map(grouped, & &1.count))}
    end)
    |> Enum.sort_by(fn %{count: count, subject: subject} -> {-count, subject} end)
  end

  defp fact_subject_from_label(label) when is_binary(label) do
    label
    |> String.split(" ", parts: 2)
    |> List.first()
    |> case do
      nil -> "unknown"
      subject -> subject
    end
  end

  defp decorate_entity_entry(%{label: label} = entry) do
    case String.split(label, ": ", parts: 2) do
      [entity_type, name] ->
        entry
        |> Map.put(:entity_type, entity_type)
        |> Map.put(:entity_name, name)

      _ ->
        entry
        |> Map.put(:entity_type, "unknown")
        |> Map.put(:entity_name, label)
    end
  end

  defp decorate_fact_entry(%{label: label} = entry) do
    parts = String.split(label, " ", parts: 3)

    case parts do
      [subject, predicate, object] ->
        entry
        |> Map.put(:subject, subject)
        |> Map.put(:predicate, predicate)
        |> Map.put(:object, object)

      [subject, predicate] ->
        entry
        |> Map.put(:subject, subject)
        |> Map.put(:predicate, predicate)
        |> Map.put(:object, "")

      [subject] ->
        entry
        |> Map.put(:subject, subject)
        |> Map.put(:predicate, "")
        |> Map.put(:object, "")

      _ ->
        entry
        |> Map.put(:subject, "")
        |> Map.put(:predicate, "")
        |> Map.put(:object, "")
    end
  end

  defp field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
