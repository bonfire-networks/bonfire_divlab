defmodule Bonfire.Divlab.Web.CreateTaskLive do
  @moduledoc """
  The composer's task type. The composer lists every type everywhere, so outside a group with Tasks on this explains where tasks are made instead of offering a form (D7a in tasks-v1.md).
  """
  use Bonfire.UI.Common.Web, :stateful_component
  alias Surface.Components.Form
  alias Surface.Components.Form.{Field, Inputs, Label, TextInput, TextArea}

  alias Bonfire.Classify.Categories
  alias Bonfire.Divlab.Tasks
  alias Bonfire.Divlab.Web.TaskRowLive

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
  data members, :list, default: []
  data loaded_context_id, :any, default: nil

  # the owner and date chips' choices, held here rather than in inputs, since the composer re-renders on every keystroke (see `Bonfire.Divlab.LiveHandler`'s `pick_task_*` events)
  data task_owner, :any, default: nil
  data task_due, :any, default: nil

  @behaviour Bonfire.UI.Common.SmartInputModule
  def smart_input_module, do: [:task, ValueFlows.Planning.Intent]
  def smart_input_icon(_), do: "ph:check-square"
  def smart_input_label(_), do: l("Create task")

  # the composer updates its active type on every keystroke's validate, so the group is only looked up when the context changes
  def update(assigns, socket) do
    socket = assign(socket, assigns |> Map.drop([:uploads]) |> assigns_clean())
    context_id = socket.assigns.context_id

    if context_id == socket.assigns.loaded_context_id do
      {:ok, socket}
    else
      group = tasks_group(context_id, socket.assigns[:__context__])

      # an owner picked in another group isn't one of this group's members
      {:ok,
       assign(socket,
         group: group,
         members: members(group, socket.assigns[:__context__]),
         loaded_context_id: context_id,
         task_owner: nil
       )}
    end
  end

  @doc """
  The member with `username`: from the loaded `members` when it's there, otherwise looked up and checked against `group` (`Bonfire.Divlab.Tasks.may_own?/2`), so members past the first 100 can be picked too; `nil` for anyone else.
  """
  def resolve_member(members, username, group) do
    find_member(members, username) ||
      with {:ok, user} <- Bonfire.Me.Users.by_username(username),
           true <- Tasks.may_own?(user, group) do
        member_entry(user)
      else
        _ -> nil
      end
  end

  @doc """
  The member in `members` (as `members/2` lists them) whose username is `username`, or `nil`.

      iex> Bonfire.Divlab.Web.CreateTaskLive.find_member([%{id: "1", name: "Mayel", username: "mayel"}], "mayel")
      %{id: "1", name: "Mayel", username: "mayel"}

      iex> Bonfire.Divlab.Web.CreateTaskLive.find_member([%{id: "1", name: "Mayel", username: "mayel"}], "Mayel")
      nil
  """
  def find_member(members, username), do: Enum.find(members, &(&1.username == username))

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

  @doc "The first 100 members of `group`, as the owner suggestions list them, for the composer and the Tasks page's Assign…."
  def members(nil, _context), do: []

  def members(group, context) do
    group
    |> Categories.list_members(current_user: current_user(context), pagination: [limit: 100])
    |> e(:edges, [])
    |> Enum.map(&member_entry/1)
  end

  @doc "A member as the owner menus show them."
  def member_entry(user) do
    username = e(user, :character, :username, "")

    %{
      id: id(user),
      name: e(user, :profile, :name, nil) || username,
      username: username,
      avatar: Media.avatar_url(user)
    }
  end
end
