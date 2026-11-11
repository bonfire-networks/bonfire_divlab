defmodule Bonfire.Divlab.Web.CreateTasksLive do
  @moduledoc """
  The composer's tasks type (tasks-v2 §13): item lines, each a checkbox, and an "Into" chip that sends them to an open list or a new list, never to no list (tasks-v2 decision 25). The composer lists every type everywhere, so outside a group with Tasks on this explains where tasks are made instead of offering a form.

  The lines live in one `phx-update="ignore"` container driven by the `Lines` hook (`create_tasks_live.hooks.js`), named `choices[i][name]` as the poll's options are, which the composer's `validate` already counts as content. The Into choice is held in this component's assigns, since the composer re-renders on every keystroke. A new list gets a name and an optional description here (tasks-v2 §15).
  """
  use Bonfire.UI.Common.Web, :stateful_component
  alias Surface.Components.Form

  alias Bonfire.Classify.Categories
  alias Bonfire.Divlab.Tasks

  prop context_id, :string, default: nil
  prop create_object_type, :any, default: nil
  prop to_boundaries, :any, default: nil
  prop to_circles, :list, default: []
  prop exclude_circles, :list, default: []
  prop smart_input_opts, :map, default: %{}
  prop showing_within, :atom, default: nil
  prop reply_to_id, :any, default: nil
  prop thread_mode, :any, default: nil
  prop uploaded_files, :list, default: nil

  data group, :any, default: nil
  data lists, :list, default: []
  # each open list's `{done, total}`, shown beside its name in the Into menu
  data progress, :map, default: %{}
  data loaded_context_id, :any, default: nil

  # where the lines go: an open list's id, or "new", which is where it starts (tasks-v2 decision 25)
  data into, :string, default: "new"

  @behaviour Bonfire.UI.Common.SmartInputModule
  def smart_input_module, do: [:task, ValueFlows.Planning.Intent]
  def smart_input_icon(_), do: "ph:check-square"
  def smart_input_label(_), do: l("Tasks")

  # the composer updates its active type on every keystroke's validate, so the group and its lists are only looked up when the context changes
  def update(assigns, socket) do
    socket = assign(socket, assigns |> Map.drop([:uploads]) |> assigns_clean())
    context_id = socket.assigns.context_id

    if context_id == socket.assigns.loaded_context_id do
      {:ok, socket}
    else
      context = socket.assigns[:__context__]
      group = tasks_group(context_id, context)
      lists = open_lists(group, context)

      {:ok,
       assign(socket,
         group: group,
         lists: lists,
         progress: Tasks.progress(Enum.map(lists, & &1.id), current_user: current_user(context)),
         loaded_context_id: context_id,
         into: "new"
       )}
    end
  end

  @doc "The label of the Into chip for `into`, given the open `lists`."
  def into_label("new", _lists), do: l("New list")

  def into_label(list_id, lists),
    do:
      Enum.find_value(
        lists,
        l("Pick a list"),
        &(&1.id == list_id && Bonfire.Divlab.Web.Preview.ListLive.list_name(&1))
      )

  # the group this would create in, if it has Tasks on; `nil` anywhere else
  defp tasks_group(nil, _context), do: nil

  defp tasks_group(context_id, context) do
    with {:ok, group} <-
           Categories.get(context_id, [:default, current_user: current_user(context)]),
         true <- Tasks.enabled_for?(group, context) do
      group
    else
      _ -> nil
    end
  end

  # the lists the lines can go into: open ones only
  defp open_lists(nil, _context), do: []

  defp open_lists(group, context) do
    {:ok, lists} = Tasks.lists(id(group), current_user: current_user(context))
    Enum.reject(lists, & &1.finished)
  end
end
