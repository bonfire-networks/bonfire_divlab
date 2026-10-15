defmodule Bonfire.Divlab.Tasks.EnabledTest do
  @moduledoc "Turning Tasks on per group (step 6 in tasks-v1.md)."
  use Bonfire.Divlab.DataCase, async: true

  import Bonfire.Me.Fake
  import Bonfire.Divlab.TasksFixtures

  alias Bonfire.Divlab.Tasks

  setup do
    owner = fake_user!()
    member = fake_user!()

    %{owner: owner, member: member, group: private_group!(owner, [member])}
  end

  test "Tasks are off in a new group", %{member: member, group: group} do
    refute Tasks.enabled_for?(group, current_user: member)
  end

  test "a group manager turns them on", %{owner: owner, member: member, group: group} do
    assert {:ok, _} = Tasks.set_enabled(group, true, current_user: owner)
    assert Tasks.enabled_for?(group, current_user: member)
  end

  test "a member who can't configure the group can't turn them on",
       %{member: member, group: group} do
    assert {:error, _} = Tasks.set_enabled(group, true, current_user: member)
    refute Tasks.enabled_for?(group, current_user: member)
  end

  test "turning them off hides them again", %{owner: owner, member: member, group: group} do
    {:ok, _} = Tasks.set_enabled(group, true, current_user: owner)
    {:ok, _} = Tasks.set_enabled(group, false, current_user: owner)

    refute Tasks.enabled_for?(group, current_user: member)
  end
end
