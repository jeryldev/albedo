defmodule Albedo.Tickets.Schema do
  @moduledoc """
  JSON schema definition for structured LLM ticket output.

  Following the instructor_lite pattern, this module provides a JSON schema
  that LLMs can use to generate properly structured ticket data.

  The schema matches the Ticket struct to ensure 100% parsing reliability.
  """

  @ticket_types ["feature", "enhancement", "bugfix", "chore", "docs", "test"]
  @priorities ["urgent", "high", "medium", "low", "none"]
  @estimate_values ["trivial", "small", "medium", "large", "extra large", "epic"]

  @doc """
  Returns the JSON schema for a single ticket.
  """
  def ticket_schema do
    %{
      "type" => "object",
      "required" => ["id", "title", "type", "priority"],
      "properties" => %{
        "id" => %{
          "type" => "string",
          "description" => "Sequential ticket number as string (e.g., \"1\", \"2\", \"3\")"
        },
        "title" => %{
          "type" => "string",
          "description" => "Clear, specific ticket title (action-oriented)",
          "maxLength" => 100
        },
        "description" => %{
          "type" => "string",
          "description" => "Detailed description of the work to be done"
        },
        "type" => %{
          "type" => "string",
          "enum" => @ticket_types,
          "description" =>
            "Ticket type: feature (new functionality), enhancement (improve existing), bugfix (fix issue), chore (maintenance), docs (documentation), test (testing)"
        },
        "priority" => %{
          "type" => "string",
          "enum" => @priorities,
          "description" =>
            "Priority level: urgent (immediate), high (important), medium (normal), low (nice to have), none (backlog)"
        },
        "estimate" => %{
          "type" => "string",
          "enum" => @estimate_values,
          "description" =>
            "Effort estimate: trivial (1 point), small (2), medium (3), large (5), extra large (8), epic (13)"
        },
        "labels" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" =>
            "Labels for categorization (e.g., backend, frontend, database, liveview)"
        },
        "acceptance_criteria" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" => "List of acceptance criteria that define done"
        },
        "implementation_notes" => %{
          "type" => "string",
          "description" => "Technical guidance and implementation details"
        },
        "files" => %{
          "type" => "object",
          "properties" => %{
            "create" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "Files to create (full paths)"
            },
            "modify" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "Files to modify (full paths)"
            }
          }
        },
        "dependencies" => %{
          "type" => "object",
          "properties" => %{
            "blocked_by" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "Ticket IDs this ticket is blocked by"
            },
            "blocks" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "Ticket IDs this ticket blocks"
            }
          }
        }
      }
    }
  end

  @doc """
  Returns the JSON schema for the complete planning response.
  """
  def planning_response_schema do
    %{
      "type" => "object",
      "required" => ["summary", "tickets"],
      "properties" => %{
        "summary" => %{
          "type" => "object",
          "required" => ["title", "description"],
          "properties" => %{
            "title" => %{
              "type" => "string",
              "description" => "Feature title derived from the task"
            },
            "description" => %{
              "type" => "string",
              "description" => "2-3 sentence summary of what this feature accomplishes"
            },
            "domain_context" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "Key domain knowledge points (3-5 items)"
            },
            "in_scope" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "Items included in this feature"
            },
            "out_of_scope" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "Items explicitly not included"
            },
            "assumptions" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "Assumptions made during planning"
            }
          }
        },
        "technical_overview" => %{
          "type" => "object",
          "properties" => %{
            "current_state" => %{
              "type" => "string",
              "description" => "How things work now"
            },
            "target_state" => %{
              "type" => "string",
              "description" => "How things will work after"
            },
            "key_changes" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "List of key technical changes"
            }
          }
        },
        "tickets" => %{
          "type" => "array",
          "items" => ticket_schema(),
          "description" => "List of actionable implementation tickets"
        },
        "implementation_order" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "ticket_id" => %{"type" => "string"},
              "reason" => %{"type" => "string"}
            }
          },
          "description" => "Recommended order to implement tickets"
        },
        "risks" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "risk" => %{"type" => "string"},
              "likelihood" => %{"type" => "string", "enum" => ["low", "medium", "high"]},
              "impact" => %{"type" => "string", "enum" => ["low", "medium", "high"]},
              "mitigation" => %{"type" => "string"}
            }
          },
          "description" => "Identified risks and mitigations"
        },
        "effort_summary" => %{
          "type" => "object",
          "properties" => %{
            "total_tickets" => %{"type" => "integer"},
            "total_points" => %{"type" => "integer"},
            "breakdown" => %{
              "type" => "object",
              "additionalProperties" => %{"type" => "integer"}
            }
          }
        }
      }
    }
  end

  @doc """
  Returns the JSON schema as a formatted string for inclusion in prompts.
  """
  def schema_as_string do
    Jason.encode!(planning_response_schema(), pretty: true)
  end

  @doc """
  Returns the ticket types.
  """
  def ticket_types, do: @ticket_types

  @doc """
  Returns the priority values.
  """
  def priorities, do: @priorities

  @doc """
  Returns the estimate values with their point mappings.
  """
  def estimate_mapping do
    %{
      "trivial" => 1,
      "small" => 2,
      "medium" => 3,
      "large" => 5,
      "extra large" => 8,
      "epic" => 13
    }
  end
end
