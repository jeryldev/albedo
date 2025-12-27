defmodule Albedo.LLM.Prompts do
  @moduledoc """
  Prompt templates for each agent type.
  """

  alias Albedo.Tickets.Schema

  @doc """
  Generate prompt for domain research phase.
  """
  def domain_research(task, context \\ %{}) do
    greenfield_section = format_greenfield_context(context)

    """
    You are a domain expert helping a software development team understand the business domain for a task.

    TASK DESCRIPTION:
    #{task}
    #{greenfield_section}

    INSTRUCTIONS:
    Analyze the task and identify the relevant domain knowledge needed to implement it correctly.

    1. Identify the primary domain (e.g., accounting, e-commerce, authentication, inventory, etc.)
    2. List core concepts and terminology specific to this domain
    3. Identify industry standards or best practices that apply
    4. List common implementation patterns used in this domain
    5. Note any compliance or regulatory requirements
    6. List edge cases and gotchas specific to this domain

    RESPONSE FORMAT:
    Respond in valid Markdown format with the following structure:

    # Domain Research: [Domain Name]

    ## Overview
    [Brief description of the domain and why it matters for this task]

    ## Core Concepts

    ### [Concept 1]
    - Definition
    - How it relates to the task
    - Key rules/constraints

    ### [Concept 2]
    [Continue for all relevant concepts]

    ## Industry Standards
    - [Standard 1 and its implications]
    - [Standard 2 and its implications]

    ## Common Implementation Patterns
    - [Pattern 1: description and when to use]
    - [Pattern 2: description and when to use]

    ## Compliance Requirements
    - [Requirement 1 if applicable]
    - [Requirement 2 if applicable]

    ## Edge Cases & Gotchas
    - [Gotcha 1: what to watch out for]
    - [Gotcha 2: what to watch out for]

    ## Implications for This Task
    [How this domain knowledge should influence the implementation]
    """
  end

  @doc """
  Generate prompt for tech stack analysis or recommendation.
  """
  def tech_stack(task, codebase_info, context \\ %{})

  def tech_stack(task, _codebase_info, %{greenfield: true} = context) do
    greenfield_section = format_greenfield_context(context)

    """
    You are a senior software engineer recommending the optimal technology stack for a new project.

    TASK DESCRIPTION:
    #{task}
    #{greenfield_section}

    INSTRUCTIONS:
    Based on the project requirements, recommend the best technology stack.
    Consider the specified stack preference if provided, but also explain alternatives.

    RESPONSE FORMAT:
    Respond in valid Markdown format with the following structure:

    # Tech Stack Recommendation

    ## Recommended Stack

    ### Primary Language
    - **Language:** [Language name]
    - **Version:** [Recommended version]
    - **Why:** [Justification]

    ### Core Framework/Libraries
    | Name | Version | Purpose | Why Chosen |
    |------|---------|---------|------------|
    | [Name] | [Version] | [Purpose] | [Justification] |

    ### Build Tools
    | Tool | Purpose |
    |------|---------|
    | [Tool] | [Purpose] |

    ## Database (if applicable)
    - **Type:** [Database type]
    - **Why:** [Justification]
    - **Alternatives:** [Other options considered]

    ## Project Structure
    ```
    [Recommended directory structure]
    ```

    ## Development Tools
    - **Formatter:** [Tool]
    - **Linter:** [Tool]
    - **Testing:** [Framework]

    ## Dependencies to Install
    ```
    [Package manager commands to set up the project]
    ```

    ## Alternatives Considered
    | Alternative | Pros | Cons | When to Choose |
    |-------------|------|------|----------------|
    | [Alt stack] | [Pros] | [Cons] | [Use case] |

    ## Getting Started
    [Step-by-step commands to initialize the project]
    """
  end

  def tech_stack(task, codebase_info, _context) do
    """
    You are a senior software engineer analyzing a codebase's technology stack.

    TASK CONTEXT:
    #{task}

    CODEBASE INFORMATION:
    #{format_codebase_info(codebase_info)}

    INSTRUCTIONS:
    Based on the codebase information, provide a comprehensive analysis of the technology stack.

    RESPONSE FORMAT:
    Respond in valid Markdown format with the following structure:

    # Tech Stack Analysis

    ## Languages
    | Language | Version | Percentage | Detection Source |
    |----------|---------|------------|------------------|
    | [Language] | [Version] | [%] | [Source file] |

    ## Frameworks & Libraries

    ### Backend
    | Name | Version | Purpose |
    |------|---------|---------|
    | [Name] | [Version] | [Purpose] |

    ### Frontend
    | Name | Version | Purpose |
    |------|---------|---------|
    | [Name] | [Version] | [Purpose] |

    ## Database
    - **Type:** [Database type]
    - **Adapter:** [Adapter name]
    - **Evidence:** [Where detected]

    ## Infrastructure
    - **Deployment:** [Platform]
    - **CI/CD:** [System]
    - **Containerization:** [Tools]

    ## Code Quality Tools
    - **Formatter:** [Tool]
    - **Linter:** [Tool]
    - **Type Checking:** [Tool if any]

    ## Testing
    - **Framework:** [Framework]
    - **Factories:** [Library if any]
    - **Mocking:** [Library if any]

    ## Key Dependencies
    [List 5-10 most important dependencies that relate to the task]
    """
  end

  @doc """
  Generate prompt for architecture analysis or planning.
  """
  def architecture(task, context)

  def architecture(task, %{greenfield: true} = context) do
    greenfield_section = format_greenfield_context(context)
    tech_stack_info = format_tech_stack_context(context)

    """
    You are a software architect designing the architecture for a new project.

    TASK DESCRIPTION:
    #{task}
    #{greenfield_section}

    TECH STACK:
    #{tech_stack_info}

    INSTRUCTIONS:
    Design a clean, scalable architecture for this new project.
    Consider best practices for the chosen tech stack.

    RESPONSE FORMAT:
    Respond in valid Markdown format with the following structure:

    # Architecture Design

    ## Overview
    [High-level description of the architecture approach]

    ## Application Type
    - **Pattern:** [Monolith / Microservices / Serverless / CLI]
    - **Style:** [MVC / Clean Architecture / Hexagonal / etc.]
    - **Justification:** [Why this approach]

    ## Module Structure

    ### Core Modules
    | Module | Purpose | Dependencies |
    |--------|---------|--------------|
    | [Module] | [Purpose] | [Dependencies] |

    ### Proposed Directory Layout
    ```
    [Directory tree structure]
    ```

    ## Data Flow

    ### Entry Points
    - [Entry point 1: description]
    - [Entry point 2: description]

    ### Data Models
    | Model | Fields | Purpose |
    |-------|--------|---------|
    | [Model] | [Key fields] | [Purpose] |

    ## Architecture Diagram

    ```mermaid
    graph TD
        [Architecture components and relationships]
    ```

    ## Key Design Decisions

    ### [Decision 1]
    - **Choice:** [What was chosen]
    - **Alternatives:** [What was considered]
    - **Rationale:** [Why this choice]

    ### [Decision 2]
    [Continue for key decisions]

    ## Extensibility Points
    - [Where the architecture can be extended]
    - [Future considerations]

    ## Testing Strategy
    - **Unit Tests:** [Approach]
    - **Integration Tests:** [Approach]
    - **E2E Tests:** [If applicable]
    """
  end

  def architecture(task, context) do
    """
    You are a software architect analyzing a codebase's structure.

    TASK CONTEXT:
    #{task}

    PREVIOUS CONTEXT:
    #{format_context(context)}

    CODEBASE STRUCTURE:
    #{context[:structure] || "Not provided"}

    INSTRUCTIONS:
    Analyze the codebase structure and provide an architecture map.

    RESPONSE FORMAT:
    Respond in valid Markdown format with the following structure:

    # Architecture Analysis

    ## Application Structure
    - **Type:** [Monolith / Umbrella / Microservices]
    - **Root namespace:** [Namespace]
    - **Web namespace:** [Web namespace if applicable]

    ## Context Map

    ### [Context Name]
    - **Purpose:** [What this context handles]
    - **Schemas:** [List of schemas]
    - **Public API:** [Key functions]
    - **Dependencies:** [Other contexts it depends on]

    [Repeat for each context]

    ## Entry Points

    ### Web Routes
    - [Route pattern] → [Handler]

    ### Background Jobs
    - [Job name and purpose]

    ## Module Relationship Diagram

    ```mermaid
    graph TD
        [Module relationships]
    ```

    ## External Integrations
    - [Integration name] - [file location]
    """
  end

  @doc """
  Generate prompt for conventions analysis.
  """
  def conventions(task, context, code_samples) do
    """
    You are a senior developer learning the conventions of an unfamiliar codebase.

    TASK CONTEXT:
    #{task}

    PREVIOUS CONTEXT:
    #{format_context(context)}

    CODE SAMPLES:
    #{code_samples}

    INSTRUCTIONS:
    Analyze the code samples and identify the conventions and patterns used in this codebase.

    RESPONSE FORMAT:
    Respond in valid Markdown format with the following structure:

    # Codebase Conventions

    ## Naming Conventions

    ### Modules
    - [Pattern observed]

    ### Functions
    - [Pattern for different function types]

    ### Files
    - [File organization pattern]

    ## Code Patterns

    ### Changesets
    ```elixir
    [Example pattern]
    ```

    ### Error Handling
    [Pattern description]

    ### Queries
    [Pattern description]

    ### Enums
    [Pattern description]

    ## Test Patterns

    ### Organization
    [Test file organization]

    ### Factories
    [Factory usage pattern]

    ### Setup
    [Common setup patterns]

    ## Migration Patterns
    [Migration naming and structure patterns]
    """
  end

  @doc """
  Generate prompt for feature location.
  """
  def feature_location(task, context, search_results) do
    """
    You are a senior engineer locating all code related to a specific feature.

    TASK DESCRIPTION:
    #{task}

    PROJECT CONTEXT:
    #{format_context(context)}

    SEARCH RESULTS:
    #{search_results}

    INSTRUCTIONS:
    Based on the search results, compile a comprehensive map of all code related to this feature.

    RESPONSE FORMAT:
    Respond in valid Markdown format with the following structure:

    # Feature Location: [Feature Name]

    ## Search Terms Used
    - Primary: [terms]
    - Secondary: [terms]

    ## Schema Definitions

    ### Primary Schema
    - **File:** [path]
    - **Line:** [line number]
    - **Code:**
      ```elixir
      [relevant code]
      ```
    - **Current type:** [type info]

    ### Related Schemas
    [Other schemas if any]

    ## Context Functions

    ### [file path]
    | Function | Line | Purpose |
    |----------|------|---------|
    | [function] | [line] | [purpose] |

    ## UI Components

    ### [file path]
    - **Line:** [range]
    - **Type:** [component type]
    - **Renders:** [what it renders]

    ## Templates
    [Template files and line numbers]

    ## Migrations
    [Migration files and their changes]

    ## Tests
    [Test files and coverage]

    ## Summary
    | Category | Files Found | Primary File |
    |----------|-------------|--------------|
    | [Category] | [count] | [file] |
    """
  end

  @doc """
  Generate prompt for impact analysis.
  """
  def impact_analysis(task, context, dependency_info) do
    """
    You are a senior engineer analyzing the impact of proposed changes.

    TASK DESCRIPTION:
    #{task}

    PROJECT CONTEXT:
    #{format_context(context)}

    DEPENDENCY INFORMATION:
    #{dependency_info}

    INSTRUCTIONS:
    Analyze all dependencies and determine what will be affected by the proposed changes.

    RESPONSE FORMAT:
    Respond in valid Markdown format with the following structure:

    # Impact Analysis: [Feature Name]

    ## Direct Dependencies (Must Change)

    These files directly use the feature and MUST be updated:

    | File | Reason | Complexity |
    |------|--------|------------|
    | [file] | [reason] | [Low/Medium/High] |

    ## Indirect Dependencies (Should Review)

    These files reference the feature and may need updates:

    | File | Usage | Risk |
    |------|-------|------|
    | [file] | [usage] | [risk level] |

    ## Query Usages

    | File | Line | Query Pattern | Impact |
    |------|------|---------------|--------|
    | [file] | [line] | [pattern] | [impact] |

    ## Side Effects

    ### Notifications
    [Notification systems affected]

    ### Background Jobs
    [Jobs affected]

    ### External APIs
    [API impacts]

    ## No Impact (Verified)
    [Areas checked with no impact]

    ## Risk Assessment

    | Risk | Severity | Mitigation |
    |------|----------|------------|
    | [risk] | [High/Medium/Low] | [mitigation] |

    ## Dependency Graph

    ```mermaid
    graph TD
        [Dependencies]
    ```
    """
  end

  @doc """
  Generate prompt for change planning (ticket generation).
  """
  def change_planning(task, context) do
    greenfield_section = format_greenfield_context(context)

    """
    You are a senior technical lead creating implementation tickets for a development team.

    TASK DESCRIPTION:
    #{task}
    #{greenfield_section}

    FULL CONTEXT:
    #{format_full_context(context)}

    INSTRUCTIONS:
    Based on all the research, create a comprehensive set of actionable tickets.
    Each ticket should be specific enough that a junior engineer can pick it up and start working.

    RESPONSE FORMAT:
    Respond in valid Markdown format with the following structure:

    # Feature: [Title from Task]

    ## Executive Summary
    [2-3 sentence summary of what this feature accomplishes]

    ## Domain Context
    [Key domain knowledge that informed this plan - 3-5 bullet points]

    ## Scope

    ### In Scope
    - [Item 1]
    - [Item 2]

    ### Out of Scope
    - [Item 1 and reason]

    ### Assumptions
    - [Assumption 1]

    ---

    ## Technical Overview

    ### Current State
    [How things work now]

    ### Target State
    [How things will work after]

    ### Key Changes
    1. [Change 1]
    2. [Change 2]

    ---

    ## Tickets

    ### Ticket #1: [Clear, Specific Title]

    **Type:** [Task | Story | Bug]
    **Priority:** [High | Medium | Low]
    **Estimate:** [Small | Medium | Large]
    **Depends On:** [None | #N]
    **Blocks:** [#N, #N]

    #### Description
    [Detailed description]

    #### Implementation Notes
    [Technical guidance]

    #### Files to Create
    | File | Purpose |
    |------|---------|
    | [path] | [purpose] |

    #### Files to Modify
    | File | Changes |
    |------|---------|
    | [path] | [changes] |

    #### Acceptance Criteria
    - [ ] [Criterion 1]
    - [ ] [Criterion 2]

    #### Risks & Notes
    - [Risk or note]

    ---

    [Repeat for all tickets]

    ---

    ## Dependency Graph

    ```mermaid
    graph LR
        T1[#1: Title] --> T2[#2: Title]
        [Continue for all dependencies]
    ```

    ## Implementation Order

    1. **#1: [Title]** - [Why first]
    2. **#2: [Title]** - [Requires #N]

    ## Risk Summary

    | Risk | Likelihood | Impact | Mitigation |
    |------|------------|--------|------------|
    | [risk] | [Low/Med/High] | [Low/Med/High] | [mitigation] |

    ## Estimated Total Effort

    | Category | Tickets | Points |
    |----------|---------|--------|
    | [Category] | [N] | [N] |
    | **Total** | **N** | **N** |
    """
  end

  defp format_codebase_info(info) when is_map(info) do
    Enum.map_join(info, "\n\n", fn {key, value} ->
      formatted_value = format_value(value)
      "#{key}:\n#{formatted_value}"
    end)
  end

  defp format_codebase_info(info), do: inspect(info)

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_list(value), do: Enum.join(value, ", ")
  defp format_value(value) when is_map(value), do: inspect(value, pretty: true)
  defp format_value(value), do: inspect(value)

  defp format_context(nil), do: "No previous context available."

  defp format_context(context) when is_map(context) do
    context
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map_join("\n", fn {key, value} ->
      """
      ### #{key |> to_string() |> String.replace("_", " ") |> String.capitalize()}
      #{summarize_context(value)}
      """
    end)
  end

  defp format_context(context), do: inspect(context)

  defp format_full_context(context) when is_map(context) do
    [
      :domain_research,
      :tech_stack,
      :architecture,
      :conventions,
      :feature_location,
      :impact_analysis
    ]
    |> Enum.map(fn key ->
      case context[key] do
        nil ->
          nil

        value ->
          "## #{key |> to_string() |> String.replace("_", " ") |> String.capitalize()}\n#{value[:content] || inspect(value)}"
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n---\n\n")
  end

  defp format_full_context(context), do: inspect(context)

  defp summarize_context(value) when is_map(value) do
    cond do
      Map.has_key?(value, :content) -> String.slice(value.content, 0, 500) <> "..."
      Map.has_key?(value, :summary) -> value.summary
      true -> inspect(value, limit: 500)
    end
  end

  defp summarize_context(value), do: inspect(value, limit: 500)

  defp format_tech_stack_context(context) when is_map(context) do
    case context[:tech_stack] do
      %{content: content} when is_binary(content) ->
        content

      _ ->
        if context[:stack] do
          "Preferred stack: #{context[:stack]}"
        else
          "No tech stack specified"
        end
    end
  end

  defp format_greenfield_context(context) when is_map(context) do
    if context[:greenfield] do
      parts = []

      parts =
        if context[:project_name],
          do: ["Project Name: #{context[:project_name]}" | parts],
          else: parts

      parts =
        if context[:stack],
          do: [
            "Tech Stack: #{context[:stack]} (IMPORTANT: Use this stack, not any mentioned in the task)"
            | parts
          ],
          else: parts

      parts =
        if context[:database],
          do: ["Database: #{context[:database]}" | parts],
          else: parts

      if parts != [] do
        "\n\nPROJECT REQUIREMENTS:\n" <> Enum.join(Enum.reverse(parts), "\n")
      else
        ""
      end
    else
      ""
    end
  end

  defp format_greenfield_context(_), do: ""

  @doc """
  Generate prompt for change planning with structured JSON output.
  This version requests JSON output matching the Ticket schema for reliable parsing.
  """
  def change_planning_structured(task, context) do
    greenfield_section = format_greenfield_context(context)

    """
    You are a senior technical lead creating implementation tickets for a development team.

    TASK DESCRIPTION:
    #{task}
    #{greenfield_section}

    FULL CONTEXT:
    #{format_full_context(context)}

    INSTRUCTIONS:
    Based on all the research, create a comprehensive set of actionable tickets.
    Each ticket should be specific enough that a junior engineer can pick it up and start working.

    IMPORTANT: Respond ONLY with valid JSON matching the schema below. No markdown, no explanations, just JSON.

    JSON SCHEMA:
    #{Schema.schema_as_string()}

    TICKET GUIDELINES:
    - id: Sequential string numbers ("1", "2", "3", etc.)
    - title: Action-oriented, clear, specific (e.g., "Add status field to journal entries schema")
    - type: #{Enum.join(Schema.ticket_types(), ", ")}
    - priority: #{Enum.join(Schema.priorities(), ", ")}
    - estimate: #{Schema.estimate_mapping() |> Map.keys() |> Enum.join(", ")}
    - acceptance_criteria: Specific, testable conditions that define "done"
    - implementation_notes: Technical guidance for implementation
    - files.create: New files to create (full paths like "lib/app/schema.ex")
    - files.modify: Existing files to modify
    - dependencies.blocked_by: Ticket IDs this depends on (e.g., ["1", "2"])
    - dependencies.blocks: Ticket IDs that depend on this

    Respond with ONLY the JSON object. No other text.
    """
  end
end
