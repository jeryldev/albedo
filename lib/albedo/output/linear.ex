defmodule Albedo.Output.Linear do
  @moduledoc """
  Linear API integration for creating tickets directly in Linear.
  This is a placeholder for future implementation.
  """

  require Logger

  @base_url "https://api.linear.app/graphql"

  @doc """
  Check if Linear integration is configured.
  """
  def configured? do
    api_key() != nil
  end

  @doc """
  Create tickets in Linear from a feature document.
  """
  def create_tickets(feature_doc, opts \\ []) do
    if configured?() do
      team_id = opts[:team_id] || default_team_id()
      project_id = opts[:project_id]

      tickets = parse_tickets(feature_doc)

      results =
        Enum.map(tickets, fn ticket ->
          create_issue(ticket, team_id, project_id)
        end)

      errors = Enum.filter(results, &match?({:error, _}, &1))

      if Enum.empty?(errors) do
        {:ok, Enum.map(results, fn {:ok, id} -> id end)}
      else
        {:error, errors}
      end
    else
      {:error, :not_configured}
    end
  end

  @doc """
  Create a single issue in Linear.
  """
  def create_issue(ticket, team_id, project_id \\ nil) do
    query = """
    mutation IssueCreate($input: IssueCreateInput!) {
      issueCreate(input: $input) {
        success
        issue {
          id
          identifier
          url
        }
      }
    }
    """

    input = %{
      "teamId" => team_id,
      "title" => ticket.title,
      "description" => ticket.description,
      "priority" => priority_to_number(ticket.priority),
      "estimate" => estimate_to_number(ticket.estimate)
    }

    input = if project_id, do: Map.put(input, "projectId", project_id), else: input

    case graphql_request(query, %{"input" => input}) do
      {:ok, %{"data" => %{"issueCreate" => %{"success" => true, "issue" => issue}}}} ->
        {:ok, issue["id"]}

      {:ok, %{"errors" => errors}} ->
        {:error, errors}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  List teams for the configured workspace.
  """
  def list_teams do
    query = """
    query Teams {
      teams {
        nodes {
          id
          name
          key
        }
      }
    }
    """

    case graphql_request(query, %{}) do
      {:ok, %{"data" => %{"teams" => %{"nodes" => teams}}}} ->
        {:ok, teams}

      {:ok, %{"errors" => errors}} ->
        {:error, errors}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  List projects for a team.
  """
  def list_projects(team_id) do
    query = """
    query Projects($teamId: String!) {
      team(id: $teamId) {
        projects {
          nodes {
            id
            name
            state
          }
        }
      }
    }
    """

    case graphql_request(query, %{"teamId" => team_id}) do
      {:ok, %{"data" => %{"team" => %{"projects" => %{"nodes" => projects}}}}} ->
        {:ok, projects}

      {:ok, %{"errors" => errors}} ->
        {:error, errors}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp api_key do
    System.get_env("LINEAR_API_KEY")
  end

  defp default_team_id do
    config = Albedo.Config.load!()
    Albedo.Config.get(config, ["output", "linear", "default_team"])
  end

  defp graphql_request(query, variables) do
    headers = [
      {"Authorization", api_key()},
      {"Content-Type", "application/json"}
    ]

    body = Jason.encode!(%{"query" => query, "variables" => variables})

    case Req.post(@base_url, body: body, headers: headers) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, response}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Linear API error (#{status}): #{inspect(body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_tickets(feature_doc) do
    Regex.scan(
      ~r/### Ticket #(\d+): (.+?)\n\n\*\*Type:\*\* (\w+)\n\*\*Priority:\*\* (\w+)\n\*\*Estimate:\*\* (\w+).*?#### Description\n(.+?)(?=####|###|\z)/s,
      feature_doc
    )
    |> Enum.map(fn [_, _num, title, type, priority, estimate, description] ->
      %{
        title: String.trim(title),
        type: String.downcase(type),
        priority: String.downcase(priority),
        estimate: String.downcase(estimate),
        description: String.trim(description)
      }
    end)
  end

  defp priority_to_number("urgent"), do: 1
  defp priority_to_number("high"), do: 2
  defp priority_to_number("medium"), do: 3
  defp priority_to_number("low"), do: 4
  defp priority_to_number(_), do: 3

  defp estimate_to_number("small"), do: 1
  defp estimate_to_number("medium"), do: 3
  defp estimate_to_number("large"), do: 5
  defp estimate_to_number(_), do: nil
end
