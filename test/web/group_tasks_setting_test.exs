defmodule Bonfire.Divlab.Web.GroupTasksSettingTest do
  @moduledoc "The group setting that turns Tasks on, and the /&group/tasks route it gates (step 6 in tasks-v1.md)."
  use Bonfire.Divlab.ConnCase, async: false

  import Bonfire.Divlab.TasksFixtures

  alias Bonfire.Classify.Categories
  alias Bonfire.Divlab.Tasks

  setup do
    # Disabled: this reset is no longer needed. The composer's types are cached app-wide (`ExtensionBehaviour.apply_modules_cached/2`) as what the modules declare, enabled or not, and the smart input handler leaves out the disabled ones when it reads them. Filling that cache while divlab is switched off in this process used to leave the task type out of every later test.
    # on_exit(fn ->
    #   Bonfire.Common.Cache.reset({Bonfire.Common.ExtensionBehaviour, :apply_modules}, [
    #     Bonfire.UI.Common.SmartInputModule.modules(),
    #     :smart_input_module
    #   ])
    # end)

    account = fake_account!()
    owner = fake_user!(account)
    group = private_group!(owner, [])

    %{account: account, owner: owner, group: group, path: "/&#{group.character.username}"}
  end

  describe "the settings row" do
    test "shows to a group manager only when the instance enables divlab",
         %{account: account, owner: owner, path: path} do
      Process.put([:bonfire_divlab, :modularity], :disabled)

      conn(user: owner, account: account)
      |> visit(path <> "/settings")
      |> refute_has("#group_settings_tasks_link")

      Process.delete([:bonfire_divlab, :modularity])

      conn(user: owner, account: account)
      |> visit(path <> "/settings")
      |> assert_has("#group_settings_tasks_link", text: "Tasks")
    end

    test "is hidden from a member who can't configure the group",
         %{account: account, owner: owner, group: group, path: path} do
      member = fake_user!(account)
      {:ok, _} = Categories.add_member(owner, group, member)

      conn(user: member, account: account)
      |> visit(path <> "/settings")
      |> refute_has("#group_settings_tasks_link")

      conn(user: owner, account: account)
      |> visit(path <> "/settings")
      |> assert_has("#group_settings_tasks_link")
    end
  end

  describe "the settings page" do
    test "turning Tasks on opens the group's Tasks page, and turning them off closes it",
         %{account: account, owner: owner, path: path} do
      session =
        conn(user: owner, account: account)
        |> visit(path <> "/settings")
        |> click_link("#group_settings_tasks_link", "Tasks")
        |> assert_has("[data-role=page_title]", text: "Tasks")
        |> check("#group_tasks_enabled", "Tasks")

      session |> visit(path <> "/tasks") |> assert_has("#group_tasks")

      session
      |> visit(path <> "/settings/tasks")
      |> uncheck("#group_tasks_enabled", "Tasks")

      session
      |> visit(path <> "/tasks")
      |> refute_has("#group_tasks")
      |> assert_has("#group_tasks_off")
    end

    test "doesn't offer the switch to a member who can't configure the group",
         %{account: account, owner: owner, group: group, path: path} do
      member = fake_user!(account)
      {:ok, _} = Categories.add_member(owner, group, member)

      conn(user: member, account: account)
      |> visit(path <> "/settings/tasks")
      |> refute_has("#group_tasks_enabled")
    end
  end

  describe "/&group/tasks" do
    test "is closed while the group hasn't turned Tasks on",
         %{account: account, owner: owner, path: path} do
      conn(user: owner, account: account)
      |> visit(path <> "/tasks")
      |> refute_has("#group_tasks")
      |> assert_has("#group_tasks_off")
    end

    test "isn't there when the instance hasn't enabled divlab, even if the group turned Tasks on",
         %{account: account, owner: owner, group: group, path: path} do
      {:ok, _} = Tasks.set_enabled(group, true, current_user: owner)
      Process.put([:bonfire_divlab, :modularity], :disabled)

      conn(user: owner, account: account)
      |> visit(path <> "/tasks")
      |> refute_has("#group_tasks")

      Process.delete([:bonfire_divlab, :modularity])

      conn(user: owner, account: account)
      |> visit(path <> "/tasks")
      |> assert_has("#group_tasks")
    end
  end
end
