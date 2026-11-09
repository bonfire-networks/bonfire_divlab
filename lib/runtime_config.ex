defmodule Bonfire.Divlab.RuntimeConfig do
  use Bonfire.Common.Localise

  @behaviour Bonfire.Common.ConfigModule
  def config_module, do: true

  @doc """
  Sets runtime configuration for the extension (typically by reading ENV variables).
  """
  def config do
    import Config

    # off unless the instance turns it on: an extension's `modularity` is how it's switched per instance (DEV-GUIDELINES); on in dev and test so it can be worked on
    config :bonfire_divlab,
      modularity:
        if(
          config_env() in [:dev, :test] or
            System.get_env("ENABLE_bonfire_divlab") in ["true", "1"],
          do: nil,
          else: :disabled
        )

    config :bonfire, :ui,
      # how a task looks in feeds (D8e), as `bonfire_poll` registers its Question; `Bonfire.Social.Feeds.LiveHandler.object_preloads/1` also asks it what to preload
      object_preview: [
        {ValueFlows.Planning.Intent, Bonfire.Divlab.Web.Preview.TaskLive},
        # a list: a card in feeds, the whole list as the main object of its own discussion page (tasks-v2 §14)
        {ValueFlows.Process, Bonfire.Divlab.Web.Preview.ListLive}
      ],
      group: [
        sections: [tasks: Bonfire.Divlab.Web.GroupTasksLive],
        settings: [
          sections: [tasks: Bonfire.Divlab.Web.GroupTasksSettingsLive],
          navigation: [
            tasks: %{
              title: l("Tasks"),
              group: :management,
              id: "group_settings_tasks_link",
              icon: "ph:check-square",
              description: l("A shared task list for this group's members"),
              module: Bonfire.Divlab.Tasks
            }
          ]
        ]
      ]

    # Acts run one after another, unlike the post and poll epics' parallel groups, so each sees what the one before assigned. The shared acts get no `attrs:` option, so they read `:post_attrs`, which a task never has: the task's `:name` never reaches `Threaded`, which would put it in a `named` mixin Intent doesn't have.
    # the post acts, in order, for whatever the first act built under `on`
    post_acts = fn on ->
      [
        {Bonfire.Social.Acts.Threaded, on: on},
        {Bonfire.Tag.Acts.Tag, on: on},
        {Bonfire.Divlab.Acts.RequireGroup, on: on},
        {Bonfire.Boundaries.Acts.SetBoundaries, on: on},
        {Bonfire.Social.Acts.Activity, on: on},
        {Bonfire.Me.Acts.Caretaker, on: on}
      ]
    end

    config :bonfire_divlab, Bonfire.Divlab.Tasks,
      epics: [
        # one item of a batch. No `Begin`/`Commit`, since `Bonfire.Divlab.Tasks` runs the whole batch in one transaction of its own (decision 7), and `Work` only opens one when there's none. Items are never boosted by the group (tasks-v2 decision 10): each has its own activity (decision 5F), and a pad import would otherwise double the feed entries. There's no `Federate` act, so nothing federates
        create_item:
          [{Bonfire.Divlab.Acts.CreateTask, on: :task, attrs: :task_attrs} | post_acts.(:task)] ++
            [Bonfire.Ecto.Acts.Work],
        # a list: the post acts on a Process (the spike, tasks-v2 §4 step 1). The group boosts it onto its timeline, as it does a post
        create_list:
          [{Bonfire.Divlab.Acts.CreateList, on: :list, attrs: :list_attrs} | post_acts.(:list)] ++
            [Bonfire.Ecto.Acts.Work, {Bonfire.Tags.Acts.AutoBoost, on: :list}]
      ]
  end
end
