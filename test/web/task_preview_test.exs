defmodule Bonfire.Divlab.Web.TaskPreviewTest do
  @moduledoc "How a task looks in feeds (step 8 in tasks-v1.md)."
  use Bonfire.Divlab.ConnCase, async: false
  use Surface.LiveViewTest

  import Bonfire.Divlab.TasksFixtures

  alias Bonfire.Divlab.Tasks

  doctest Bonfire.Divlab.Web.Preview.TaskLive

  setup do
    account = fake_account!()
    ivan = fake_user!(account)
    mayel = fake_user!(account)
    group = tasks_group!(ivan, [mayel])

    %{
      account: account,
      ivan: ivan,
      mayel: mayel,
      group: group,
      path: "/&#{group.character.username}"
    }
  end

  # the group no longer boosts items onto its timeline (tasks-v2 decision 10), so the card is checked in the members' Local feed
  test "in members' Local feed a task shows as a task, linking to the group's Tasks page",
       %{account: account, ivan: ivan, mayel: mayel, group: group} do
    task!(ivan, group, "Call the printer",
      provider_id: mayel.id,
      note: "About the flyers"
    )

    conn(user: ivan, account: account)
    |> visit("/feed/local")
    |> assert_has("[data-role=task_preview]", text: "Call the printer")
    |> assert_has("[data-role=task_preview]", text: "About the flyers")
    |> assert_has("[data-role=task_preview] [data-role=task_owner]", text: mayel.profile.name)
    |> assert_has("[data-role=task_preview] a[href='#{Bonfire.Common.URIs.path(group)}/tasks']")
  end

  test "a finished task shows as done", %{account: account, ivan: ivan, group: group} do
    task = task!(ivan, group, "Fix the gate", provider_id: ivan.id)
    {:ok, _} = Tasks.done(task.id, current_user: ivan)

    conn(user: ivan, account: account)
    |> visit("/feed/local")
    |> assert_has("[data-role=task_preview][data-done]", text: "Fix the gate")
    |> assert_has("[data-role=task_preview] .sr-only", text: "Done")
  end

  test "an open task with no owner says it's unassigned",
       %{account: account, ivan: ivan, group: group} do
    task!(ivan, group, "Book the hut")

    conn(user: ivan, account: account)
    |> visit("/feed/local")
    |> assert_has("[data-role=task_preview] [data-role=task_unassigned]", text: "Unassigned")
  end

  # rendered directly: `ActivityLive` sets `activity_inception` on a reply's parent and on quotes
  test "above a reply a task shows only its title", %{ivan: ivan, group: group} do
    assigns = %{
      task: task!(ivan, group, "Call the printer", note: "About the flyers")
    }

    html =
      render_surface do
        ~F"""
        <Bonfire.Divlab.Web.Preview.TaskLive object={@task} activity_inception="reply_to" />
        """
      end

    assert html =~ "Call the printer"
    refute html =~ "About the flyers"
  end
end
