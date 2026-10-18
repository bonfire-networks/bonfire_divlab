defmodule Bonfire.Divlab.Web.CreateTaskTest do
  @moduledoc "Creating a task from the composer (step 7 in tasks-v1.md)."
  use Bonfire.Divlab.ConnCase, async: false

  import Bonfire.Divlab.TasksFixtures

  alias Bonfire.Classify.Categories
  alias Bonfire.Divlab.Tasks

  doctest Bonfire.Divlab.Web.CreateTaskLive

  setup do
    account = fake_account!()
    me = fake_user!(account)
    mayel = fake_user!(account)
    group = private_group!(me, [mayel])
    {:ok, _} = Tasks.set_enabled(group, true, current_user: me)

    %{account: account, me: me, mayel: mayel, group: group, path: "/&#{group.character.username}"}
  end

  test "New task on the Tasks page opens the task composer, and the task lands in the Inbox",
       %{account: account, me: me, group: group, path: path} do
    conn(user: me, account: account)
    |> visit(path <> "/tasks")
    |> click_button("#group_tasks_new", "New task")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      assert has_element?(composer, "#composer_type_chooser_trigger", "Create task")

      composer
      |> form("#smart_input_task_content form",
        post: %{post_content: %{name: "Water the plants"}, note: "Every *Tuesday*"}
      )
      |> render_submit()

      render(view)
    end)

    assert names(:inbox, me, group) == ["Water the plants"]
  end

  test "typing a title enables the submit button", %{account: account, me: me, path: path} do
    conn(user: me, account: account)
    |> visit(path <> "/tasks")
    |> click_button("#group_tasks_new", "New task")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      assert has_element?(composer, "#submit_btn[disabled]")

      composer
      |> form("#smart_input_task_content form",
        post: %{post_content: %{name: "Water the plants"}}
      )
      |> render_change()

      assert has_element?(composer, "#submit_btn:not([disabled])")
      render(view)
    end)
  end

  test "the owner menu lists the group's members and nobody else",
       %{account: account, me: me, group: group, path: path} do
    member = fake_user!(account)
    {:ok, _} = Categories.add_member(me, group, member)
    outsider = fake_user!(account)

    conn(user: me, account: account)
    |> visit(path <> "/tasks")
    |> click_button("#group_tasks_new", "New task")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)

      assert has_element?(composer, "#task_owner_option_#{member.id}")
      refute has_element?(composer, "#task_owner_option_#{outsider.id}")

      assert has_element?(
               composer,
               "#task_owner_options option[value='#{member.character.username}']"
             )

      refute has_element?(
               composer,
               "#task_owner_options option[value='#{outsider.character.username}']"
             )

      render(view)
    end)
  end

  test "an owner picked on the chip owns the task, also after typing the title",
       %{account: account, me: me, mayel: mayel, group: group, path: path} do
    conn(user: me, account: account)
    |> visit(path <> "/tasks")
    |> click_button("#group_tasks_new", "New task")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      composer |> element("#task_owner_option_#{mayel.id}") |> render_click()
      assert has_element?(composer, "[data-role=task_owner_chip]", mayel.profile.name)

      # typing re-renders the composer, which mustn't drop the picked owner
      form =
        form(composer, "#smart_input_task_content form",
          post: %{post_content: %{name: "Fix the gate"}}
        )

      render_change(form)
      assert has_element?(composer, "[data-role=task_owner_chip]", mayel.profile.name)

      render_submit(form)
      render(view)
    end)

    assert names(:mine, mayel, group) == ["Fix the gate"]
  end

  test "typing a member's username in the owner search picks them",
       %{account: account, me: me, mayel: mayel, path: path} do
    conn(user: me, account: account)
    |> visit(path <> "/tasks")
    |> click_button("#group_tasks_new", "New task")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)

      composer
      |> element("#task_owner_search")
      |> render_submit(%{"owner" => mayel.character.username})

      assert has_element?(composer, "[data-role=task_owner_chip]", mayel.profile.name)
      render(view)
    end)
  end

  test "an owner who isn't a member is refused, from the search or sent with the task",
       %{account: account, me: me, group: group, path: path} do
    outsider = fake_user!(account)

    conn(user: me, account: account)
    |> visit(path <> "/tasks")
    |> click_button("#group_tasks_new", "New task")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)

      composer
      |> element("#task_owner_search")
      |> render_submit(%{"owner" => outsider.character.username})

      assert has_element?(composer, "[data-role=task_owner_chip]", "Owner")

      composer
      |> form("#smart_input_task_content form", post: %{post_content: %{name: "Fix the gate"}})
      |> render_submit(%{"post" => %{"owner_id" => outsider.id}})

      render(view)
    end)

    assert names(:inbox, me, group) == []
    assert names(:waiting, me, group) == []
  end

  test "the owner search finds a member who isn't in the loaded list, and nobody else",
       %{account: account, mayel: mayel, group: group} do
    assert %{id: id} =
             Bonfire.Divlab.Web.CreateTaskLive.resolve_member([], mayel.character.username, group)

    assert id == mayel.id

    assert is_nil(
             Bonfire.Divlab.Web.CreateTaskLive.resolve_member(
               [],
               fake_user!(account).character.username,
               group
             )
           )
  end

  test "clearing the date input on the chip clears the date",
       %{account: account, me: me, path: path} do
    conn(user: me, account: account)
    |> visit(path <> "/tasks")
    |> click_button("#group_tasks_new", "New task")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      composer |> element("#task_due_option_tomorrow") |> render_click()
      composer |> element("#task_due_pick") |> render_change(%{"due" => ""})

      assert has_element?(composer, "[data-role=task_due_chip]", "Due date")
      render(view)
    end)
  end

  test "a date picked on the chip is the task's date, and No date clears it",
       %{account: account, me: me, group: group, path: path} do
    conn(user: me, account: account)
    |> visit(path <> "/tasks")
    |> click_button("#group_tasks_new", "New task")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      composer |> element("#task_due_option_tomorrow") |> render_click()
      assert has_element?(composer, "[data-role=task_due_chip]", "Tomorrow")

      composer |> element("#task_due_clear") |> render_click()
      assert has_element?(composer, "[data-role=task_due_chip]", "Due date")

      composer |> element("#task_due_option_tomorrow") |> render_click()

      composer
      |> form("#smart_input_task_content form", post: %{post_content: %{name: "Fix the gate"}})
      |> render_submit()

      render(view)
    end)

    assert names(:due_soon, me, group) == ["Fix the gate"]
  end

  test "a task I give myself is in my Mine", %{account: account, me: me, group: group, path: path} do
    create_from_composer(account, me, path, name: "Fix the gate", owner: me)

    assert names(:mine, me, group) == ["Fix the gate"]
  end

  test "tasks I give Mayel with dates are in my Waiting on, soonest first",
       %{account: account, me: me, mayel: mayel, group: group, path: path} do
    create_from_composer(account, me, path, name: "Later", owner: mayel, due: in_date(5))
    create_from_composer(account, me, path, name: "Sooner", owner: mayel, due: in_date(2))

    assert names(:waiting, me, group) == ["Sooner", "Later"]
    assert names(:mine, mayel, group) == ["Sooner", "Later"]
  end

  test "the task composer has no form outside a group with Tasks on",
       %{account: account, me: me, group: group, path: path} do
    {:ok, _} = Tasks.set_enabled(group, false, current_user: me)

    conn(user: me, account: account)
    |> visit(path)
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)

      composer
      |> element("#composer_type_chooser a[phx-click*='CreateTaskLive']")
      |> render_click()

      assert has_element?(composer, "#smart_input_task_unavailable")
      refute has_element?(composer, "#smart_input_task_content form")
      render(view)
    end)
  end

  # picks the owner and the date on the chips, as a click and a picked date do, then submits the title and anything else in `attrs`
  defp create_from_composer(account, user, path, attrs) do
    {owner, attrs} = Keyword.pop(attrs, :owner)
    {due, attrs} = Keyword.pop(attrs, :due)
    {name, attrs} = Keyword.pop!(attrs, :name)

    conn(user: user, account: account)
    |> visit(path <> "/tasks")
    |> click_button("#group_tasks_new", "New task")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      if owner, do: composer |> element("#task_owner_option_#{owner.id}") |> render_click()
      if due, do: composer |> element("#task_due_pick") |> render_change(%{"due" => due})

      composer
      |> form("#smart_input_task_content form",
        post: attrs |> Map.new() |> Map.put(:post_content, %{name: name})
      )
      |> render_submit()

      render(view)
    end)
  end

  # what a date input sends
  defp in_date(days), do: Date.utc_today() |> Date.add(days) |> Date.to_iso8601()
end
