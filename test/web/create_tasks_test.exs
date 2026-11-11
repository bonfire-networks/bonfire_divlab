defmodule Bonfire.Divlab.Web.CreateTasksTest do
  @moduledoc "Adding items, and new lists, from the composer (tasks-v2 §13)."
  use Bonfire.Divlab.ConnCase, async: false

  import Bonfire.Divlab.TasksFixtures

  alias Bonfire.Divlab.Tasks

  doctest Bonfire.Divlab.Web.CreateTasksLive

  setup do
    account = fake_account!()
    me = fake_user!(account)
    mayel = fake_user!(account)
    group = tasks_group!(me, [mayel])

    %{account: account, me: me, group: group, path: "/&#{group.character.username}"}
  end

  # the composer makes no items without a list: Into starts on New list (tasks-v2 decision 25)
  test "Into starts on New list, with no No list option; picking a list adds the lines to it, and the toast names it",
       %{account: account, me: me, group: group, path: path} do
    list = create_list!(me, group, %{name: "Launch"})

    with_composer(account, me, path, fn composer ->
      assert has_element?(composer, "[data-role=tasks_into_chip]", "New list")
      refute has_element?(composer, "#tasks_into_option_none")

      composer |> element("#tasks_into_option_#{list.id}") |> render_click()
      submit(composer, ["Write the note", "Archive the pad"])
      assert render(composer) =~ "2 items added to Launch"
    end)

    assert item_names(list.id, me) == ["Write the note", "Archive the pad"]
  end

  test "a submit with no list is refused and creates nothing",
       %{account: account, me: me, group: group, path: path} do
    with_composer(account, me, path, fn composer ->
      # a forged form: the page itself has no "none" to send
      composer
      |> form("#smart_input_tasks_content form")
      |> render_submit(%{
        "post" => %{"into" => "none"},
        "choices" => %{"0" => %{"name" => "Loose one"}}
      })

      assert render(composer) =~ "Pick a list, or start a new one"
    end)

    assert {:ok, []} = Tasks.list(:inbox, group.id, current_user: me)
  end

  test "New list with a name and a description creates the list with the lines",
       %{account: account, me: me, group: group, path: path} do
    with_composer(account, me, path, fn composer ->
      composer |> element("#tasks_into_option_new") |> render_click()

      submit(composer, ["First", "Second"],
        post: %{post_content: %{name: "Sprint 47"}, list_note: "What we ship this round"}
      )
    end)

    assert {:ok, [list]} = Tasks.lists(group.id, current_user: me)
    assert list.name == "Sprint 47"
    assert list.note == "What we ship this round"
    assert item_names(list.id, me) == ["First", "Second"]
  end

  test "a `- [x]` line comes in done", %{account: account, me: me, group: group, path: path} do
    list = create_list!(me, group, %{name: "Launch"})

    with_composer(account, me, path, fn composer ->
      composer |> element("#tasks_into_option_#{list.id}") |> render_click()
      submit(composer, ["- [x] Already done", "- [ ] Still to do"])
    end)

    assert {:ok, items} = Tasks.items(list.id, current_user: me)

    assert Enum.map(items, &{&1.name, &1.finished}) == [
             {"Already done", true},
             {"Still to do", false}
           ]
  end

  test "New list with no name shows an error and creates nothing",
       %{account: account, me: me, group: group, path: path} do
    with_composer(account, me, path, fn composer ->
      composer |> element("#tasks_into_option_new") |> render_click()
      submit(composer, ["Orphan"])
      assert render(composer) =~ "Could not add the tasks"
    end)

    assert {:ok, []} = Tasks.lists(group.id, current_user: me)
    assert {:ok, []} = Tasks.list(:inbox, group.id, current_user: me)
  end

  test "the composer has no form outside a group with Tasks on",
       %{account: account, me: me, group: group, path: path} do
    {:ok, _} = Tasks.set_enabled(group, false, current_user: me)

    conn(user: me, account: account)
    |> visit(path)
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)

      composer
      |> element("#composer_type_tray_rail button[phx-click*='CreateTasksLive']")
      |> render_click()

      assert has_element?(composer, "#smart_input_task_unavailable")
      refute has_element?(composer, "#smart_input_tasks_content form")
      render(view)
    end)
  end

  # opens the composer from the group's Tasks page, as "Add tasks" does, and runs `fun` on it
  defp with_composer(account, user, path, fun) do
    conn(user: user, account: account)
    |> visit(path <> "/tasks")
    |> click_button("#group_tasks_new", "Add tasks")
    |> PhoenixTest.unwrap(fn view ->
      view |> composer_view() |> fun.()
      render(view)
    end)
  end

  # submits `lines` as the `Lines` hook numbers them (the hook itself is JS, so the browser pass checks it). `form_data` fills fields the form has, so its hidden `post[into]` keeps what the chip picked
  defp submit(composer, lines, form_data \\ []) do
    choices =
      lines |> Enum.with_index() |> Map.new(fn {line, i} -> {to_string(i), %{"name" => line}} end)

    composer
    |> form("#smart_input_tasks_content form", form_data)
    |> render_submit(%{"choices" => choices})
  end

  defp create_list!(user, group, attrs) do
    {:ok, %{list: list}} =
      Tasks.create_list(attrs, [],
        current_user: user,
        context_id: group.id,
        boundary: "members:private"
      )

    list
  end

  defp item_names(list_id, user) do
    {:ok, items} = Tasks.items(list_id, current_user: user)
    Enum.map(items, & &1.name)
  end
end
