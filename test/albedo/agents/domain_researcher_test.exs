defmodule Albedo.Agents.DomainResearcherTest do
  use ExUnit.Case, async: true

  describe "domain detection" do
    test "detects accounting domain" do
      assert detect_domain("Add ledger entries for journal posting") == :accounting
      assert detect_domain("Implement debit and credit balancing") == :accounting
      assert detect_domain("Add GAAP compliance checks") == :accounting
    end

    test "detects authentication domain" do
      assert detect_domain("Add user login functionality") == :authentication
      assert detect_domain("Implement OAuth authentication") == :authentication
      assert detect_domain("Add session management") == :authentication
    end

    test "detects ecommerce domain" do
      assert detect_domain("Add shopping cart feature") == :ecommerce
      assert detect_domain("Implement checkout flow") == :ecommerce
      assert detect_domain("Add product inventory management") == :ecommerce
    end

    test "detects payments domain" do
      assert detect_domain("Integrate Stripe payments") == :payments
      assert detect_domain("Add subscription billing") == :payments
      assert detect_domain("Implement refund processing") == :payments
    end

    test "detects inventory domain" do
      assert detect_domain("Add warehouse stock tracking") == :inventory
      assert detect_domain("Implement FIFO inventory method") == :inventory
    end

    test "detects compliance domain" do
      assert detect_domain("Add GDPR consent management") == :compliance
      assert detect_domain("Implement data deletion for privacy") == :compliance
    end

    test "detects reporting domain" do
      assert detect_domain("Create dashboard with analytics") == :reporting
      assert detect_domain("Add KPI visualization charts") == :reporting
    end

    test "detects notifications domain" do
      assert detect_domain("Send email notifications") == :notifications
      assert detect_domain("Add webhook integrations") == :notifications
    end

    test "detects scheduling domain" do
      assert detect_domain("Add calendar booking feature") == :scheduling
      assert detect_domain("Implement recurring appointments") == :scheduling
    end

    test "detects workflow domain" do
      assert detect_domain("Add approval workflow") == :workflow
      assert detect_domain("Implement state transitions") == :workflow
    end

    test "returns general for unknown domain" do
      assert detect_domain("Add a hello world feature") == :general
      assert detect_domain("Fix the bug") == :general
    end

    test "handles mixed domain keywords with highest score" do
      assert detect_domain("Add login for payment processing") in [:authentication, :payments]
    end
  end

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
