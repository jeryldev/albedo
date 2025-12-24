defmodule Albedo.Agents.DomainResearcher do
  @moduledoc """
  Phase 0: Domain Research Agent.
  Understands the domain knowledge required to implement the task correctly.
  """

  use Albedo.Agents.Base

  alias Albedo.LLM.Prompts

  @domain_keywords %{
    accounting:
      ~w(ledger journal debit credit balance account transaction reconciliation gaap ifrs audit),
    authentication:
      ~w(login logout session token oauth oidc sso password auth authentication authorization),
    ecommerce: ~w(cart checkout order payment product inventory shipping discount coupon),
    payments: ~w(payment stripe charge refund subscription billing invoice pci),
    inventory: ~w(stock inventory warehouse product sku quantity fifo lifo),
    compliance: ~w(gdpr privacy consent data retention deletion portability),
    reporting: ~w(report dashboard analytics metric kpi chart graph visualization),
    notifications: ~w(notification email sms push alert webhook),
    scheduling: ~w(schedule calendar appointment booking event recurring),
    workflow: ~w(workflow state status transition approval pipeline)
  }

  @impl Albedo.Agents.Base
  def investigate(state) do
    task = state.task
    context = state.context
    detected_domain = detect_domain(task)

    prompt = Prompts.domain_research(task, context)

    case call_llm(prompt) do
      {:ok, response} ->
        findings = %{
          task: task,
          detected_domain: detected_domain,
          content: response
        }

        {:ok, findings}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Albedo.Agents.Base
  def format_output(findings) do
    findings.content
  end

  defp detect_domain(task) do
    task_lower = String.downcase(task)

    @domain_keywords
    |> Enum.map(fn {domain, keywords} ->
      score = Enum.count(keywords, fn kw -> String.contains?(task_lower, kw) end)
      {domain, score}
    end)
    |> Enum.filter(fn {_, score} -> score > 0 end)
    |> Enum.sort_by(fn {_, score} -> score end, :desc)
    |> case do
      [{domain, _} | _] -> domain
      [] -> :general
    end
  end
end
