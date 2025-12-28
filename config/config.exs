import Config

config :logger, :console,
  metadata: [
    :project_id,
    :task,
    :project_name,
    :current_phase,
    :phase,
    :reason,
    :provider,
    :model,
    :prompt_length,
    :duration_ms,
    :response_length,
    :error
  ]
