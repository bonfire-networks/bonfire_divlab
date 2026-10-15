defmodule Bonfire.Divlab.Web.TaskDiscussionTest do
  @moduledoc "A task's discussion, where it can be liked, boosted, bookmarked and replied to like a post (D9 in tasks-v1.md)."
  use Bonfire.Divlab.ConnCase, async: false

  import Bonfire.Divlab.TasksFixtures

  setup do
    account = fake_account!()
    ivan = fake_user!(account)
    mayel = fake_user!(account)
    group = tasks_group!(ivan, [mayel])

    %{account: account, ivan: ivan, mayel: mayel, group: group}
  end

  test "a member sees the task with its actions and the replies to it",
       %{account: account, ivan: ivan, mayel: mayel, group: group} do
    task = task!(ivan, group, "Call the printer", provider_id: mayel.id)

    {:ok, _reply} =
      Bonfire.Posts.publish(
        current_user: mayel,
        context_id: group.id,
        boundary: "members:private",
        post_attrs: %{post_content: %{html_body: "I can do Friday"}, reply_to_id: task.id}
      )

    conn(user: mayel, account: account)
    |> visit("/discussion/#{task.id}")
    |> assert_has("[data-role=task_preview]", text: "Call the printer")
    |> assert_has("[data-id=like_action]")
    |> assert_has("[data-id=boost_action]")
    |> assert_has("[data-id=bookmark_action]")
    |> assert_has("[data-id=comment]", text: "I can do Friday")
  end

  test "a non-member and a guest see nothing of it",
       %{account: account, ivan: ivan, group: group} do
    task = task!(ivan, group, "Call the printer")
    outsider = fake_user!(account)

    for session <- [conn(user: outsider, account: account), conn()] do
      session
      |> visit("/discussion/#{task.id}")
      |> refute_has("body", text: "Call the printer")
    end
  end
end
