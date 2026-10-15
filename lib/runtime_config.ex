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
        {ValueFlows.Planning.Intent, Bonfire.Divlab.Web.Preview.TaskLive}
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
    config :bonfire_divlab, Bonfire.Divlab.Tasks,
      epics: [
        create: [
          {Bonfire.Divlab.Acts.CreateTask, on: :task, attrs: :task_attrs},
          {Bonfire.Social.Acts.Threaded, on: :task},
          {Bonfire.Tag.Acts.Tag, on: :task},
          {Bonfire.Divlab.Acts.RequireGroup, on: :task},
          {Bonfire.Boundaries.Acts.SetBoundaries, on: :task},
          {Bonfire.Social.Acts.Activity, on: :task},
          {Bonfire.Me.Acts.Caretaker, on: :task},
          Bonfire.Ecto.Acts.Begin,
          Bonfire.Ecto.Acts.Work,
          Bonfire.Ecto.Acts.Commit,
          # the group boosts the task onto its timeline, as it does a post. There's no `Federate` act, so the task has no AP object and the boost isn't announced (`Bonfire.Social.Boosts.ap_publish_activity/3`)
          {Bonfire.Tags.Acts.AutoBoost, on: :task}
        ]
      ]
  end
end
