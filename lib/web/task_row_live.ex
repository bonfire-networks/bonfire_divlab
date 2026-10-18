defmodule Bonfire.Divlab.Web.TaskRowLive do
  @moduledoc "A task on the Tasks page (D8c in tasks-v1.md). Its actions go to `event_target`, the board, which reloads every view after one."
  use Bonfire.UI.Common.Web, :stateless_component

  prop task, :any, required: true
  prop view, :atom, required: true
  prop members, :list, default: []
  prop may_delete, :boolean, default: false
  prop event_target, :any, required: true

  def render(assigns) do
    assigns
    |> assign(:done?, e(assigns.task, :finished, false) == true)
    |> render_sface()
  end

  @doc """
  What the row hands the preview modal to open the task's discussion, as a feed activity does (`Bonfire.UI.Social.ActivityLive.thread_preview_modal_assigns/6`). Without the task itself, so the thread loads it with its activity the way `/discussion/:id` does, and the actions and replies show.
  """
  def preview_assigns(task) do
    task_id = id(task)

    Bonfire.UI.Social.ActivityLive.thread_preview_modal_assigns(
      task_id,
      task_id,
      task_id,
      nil,
      nil,
      nil
    )
    |> Keyword.merge(current_url: "/discussion/#{task_id}", cw: false)
  end

  @doc """
  The short label for a due date, a `DateTime` as stored or a `Date` as the composer's chip holds it: Today, Tomorrow or Yesterday, the weekday within the coming week, otherwise the day and month, with the year when it isn't this year.

      iex> Bonfire.Divlab.Web.TaskRowLive.due_label(~U[2026-10-15 00:00:00Z], ~D[2026-10-15])
      "Today"

      iex> Bonfire.Divlab.Web.TaskRowLive.due_label(~D[2026-10-16], ~D[2026-10-15])
      "Tomorrow"

      iex> Bonfire.Divlab.Web.TaskRowLive.due_label(~U[2026-10-16 00:00:00Z], ~D[2026-10-15])
      "Tomorrow"

      iex> Bonfire.Divlab.Web.TaskRowLive.due_label(~U[2026-10-19 00:00:00Z], ~D[2026-10-15])
      "Mon"

      iex> Bonfire.Divlab.Web.TaskRowLive.due_label(~U[2026-11-03 00:00:00Z], ~D[2026-10-15])
      "Nov 3"

      iex> Bonfire.Divlab.Web.TaskRowLive.due_label(~U[2027-01-05 00:00:00Z], ~D[2026-10-15])
      "Jan 5, 2027"
  """
  def due_label(due, today \\ Date.utc_today())

  def due_label(%DateTime{} = due, today), do: due |> DateTime.to_date() |> due_label(today)

  def due_label(%Date{} = date, today) do
    case Date.diff(date, today) do
      0 ->
        l("Today")

      1 ->
        l("Tomorrow")

      -1 ->
        l("Yesterday")

      days when days in 2..6 ->
        Bonfire.Common.DatesTimes.format_date(date, format: "EEE")

      _ when date.year == today.year ->
        Bonfire.Common.DatesTimes.format_date(date, format: "MMM d")

      _ ->
        Bonfire.Common.DatesTimes.format_date(date)
    end
  end

  @doc """
  The date popover's shortcuts: today, tomorrow, and next Monday.

      iex> ~D[2026-10-15]
      ...> |> Bonfire.Divlab.Web.TaskRowLive.quick_dates()
      ...> |> Enum.map(fn {key, _label, date} -> {key, date} end)
      [today: ~D[2026-10-15], tomorrow: ~D[2026-10-16], next_week: ~D[2026-10-19]]
  """
  def quick_dates(today \\ Date.utc_today()) do
    [
      {:today, l("Today"), today},
      {:tomorrow, l("Tomorrow"), Date.add(today, 1)},
      {:next_week, l("Next week"), Date.add(today, 8 - Date.day_of_week(today))}
    ]
  end

  @doc """
  Whether `task`'s date is before `today`, which the row and the feed card show in red. A task due today isn't overdue yet, and a finished one never is.

      iex> Bonfire.Divlab.Web.TaskRowLive.overdue?(%{due: ~U[2020-01-01 00:00:00Z]}, ~D[2020-01-02])
      true

      iex> Bonfire.Divlab.Web.TaskRowLive.overdue?(%{due: ~U[2020-01-01 00:00:00Z], finished: true}, ~D[2020-01-02])
      false

      iex> Bonfire.Divlab.Web.TaskRowLive.overdue?(%{due: ~U[2020-01-02 00:00:00Z]}, ~D[2020-01-02])
      false

      iex> Bonfire.Divlab.Web.TaskRowLive.overdue?(%{due: nil}, ~D[2020-01-02])
      false
  """
  def overdue?(task, today \\ Date.utc_today())

  def overdue?(%{finished: true}, _today), do: false

  def overdue?(%{due: %DateTime{} = due}, today),
    do: Date.compare(DateTime.to_date(due), today) == :lt

  def overdue?(_task, _today), do: false

  @doc "The name the row and the feed card show for `task`'s owner, from its preloaded provider."
  def owner_name(task),
    do: e(task, :provider, :profile, :name, nil) || e(task, :provider, :character, :username, nil)
end
