defmodule Bonfire.Divlab.Web.Preview.ListLive do
  @moduledoc """
  A list (a `ValueFlows.Process`) wherever Bonfire shows an object (tasks-v2 §14), as `bonfire_poll`'s `QuestionLive` is for a poll. In a feed: its name, whether it's closed, its progress and first open items, linking to its page. As the main object of its own discussion page: the whole list, `Bonfire.Divlab.Web.ListPageLive`, with the replies below.

  The card reads its list's counts and first open items once per card, as the poll card reads its votes (`Bonfire.Poll.Web.Preview.QuestionLive.view_state/4`), through their boundaries.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  alias Bonfire.Divlab.Tasks

  prop object, :any
  prop activity_component_id, :any, default: nil
  prop activity, :any, default: nil
  prop viewing_main_object, :boolean, default: false
  prop showing_within, :atom, default: nil
  prop cw, :boolean, default: nil
  prop is_remote, :boolean, default: false
  prop thread_title, :any, default: nil
  prop hide_actions, :boolean, default: false
  # `ActivityLive` passes what the activity is shown within (eg. `"preview"`), not a boolean
  prop activity_inception, :any, default: nil
  prop permalink, :string, default: nil

  # how many open items the card shows
  @card_items 3

  @doc "What a feed preloads for each list: `Bonfire.Social.Feeds.LiveHandler.object_preloads/1` asks whichever component `[:ui, :object_preview]` registers for a Process, so the activity's author has a name."
  def preloads, do: [creator: [:profile, :character]]

  def render(%{viewing_main_object: true} = assigns), do: render_sface(assigns)

  # the counts in one query and only the open items it shows, rather than every item (still per card, decision 16)
  def render(assigns) do
    {done, total, open_items} = card_items(assigns.object, assigns[:__context__])

    assigns
    |> assign(
      progress: progress_label(done, total),
      open_items: open_items,
      more: max(total - done - length(open_items), 0)
    )
    |> render_sface()
  end

  @doc """
  A list's name, or "Untitled list" when it has none.

      iex> Bonfire.Divlab.Web.Preview.ListLive.list_name(%{name: nil})
      "Untitled list"
  """
  def list_name(list), do: e(list, :name, nil) || l("Untitled list")

  @doc """
  The progress line for `done` of `total` items.

      iex> Bonfire.Divlab.Web.Preview.ListLive.progress_label(1, 2)
      "1 of 2 done"

      iex> Bonfire.Divlab.Web.Preview.ListLive.progress_label(0, 0)
      "No items yet"
  """
  def progress_label(_done, 0), do: l("No items yet")
  def progress_label(done, total), do: l("%{done} of %{total} done", done: done, total: total)

  defp card_items(%{id: list_id}, context) do
    me = current_user(context)
    {done, total} = Tasks.progress([list_id], current_user: me) |> Map.get(list_id, {0, 0})
    {:ok, open_items} = Tasks.open_items(list_id, @card_items, current_user: me)
    {done, total, open_items}
  end

  defp card_items(_, _), do: {0, 0, []}
end
