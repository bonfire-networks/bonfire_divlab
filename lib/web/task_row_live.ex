defmodule Bonfire.Divlab.Web.TaskRowLive do
  @moduledoc "A task row (D8c in tasks-v1.md), on the Tasks page or, `editable`, on a list's page. Its actions go to `event_target`, the board or the list page, which reloads its rows after one."
  use Bonfire.UI.Common.Web, :stateless_component

  prop task, :any, required: true
  prop view, :atom, required: true
  prop members, :list, default: []
  prop may_delete, :boolean, default: false
  prop event_target, :any, required: true
  # on a list's page, the title is a line to write in (tasks-v2 §14)
  prop editable, :boolean, default: false
  # in the cross-list views, the name of the list the task is in
  prop show_list, :boolean, default: false

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

  @doc "The name the row and the feed card show for `task`'s owner, from its preloaded provider."
  def owner_name(task),
    do: e(task, :provider, :profile, :name, nil) || e(task, :provider, :character, :username, nil)
end
