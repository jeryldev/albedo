defmodule Albedo.Test.LLMMock do
  @moduledoc """
  Mock LLM responses for testing.
  """

  @doc """
  Returns a mock domain research response.
  """
  def domain_research_response do
    """
    # Domain Research: E-commerce

    ## Overview
    E-commerce involves online buying and selling of goods and services.

    ## Core Concepts

    ### Order Management
    - Definition: Tracking orders from creation to fulfillment
    - Key rules: Orders must have valid status transitions

    ### Shopping Cart
    - Definition: Temporary storage for items before purchase
    - Key rules: Cart must handle inventory availability

    ## Industry Standards
    - PCI DSS for payment handling
    - GDPR for customer data

    ## Common Implementation Patterns
    - Event sourcing for order state
    - Saga pattern for distributed transactions

    ## Edge Cases & Gotchas
    - Race conditions in inventory updates
    - Price changes during checkout
    """
  end

  @doc """
  Returns a mock tech stack response.
  """
  def tech_stack_response do
    """
    # Tech Stack Analysis

    ## Languages
    | Language | Version | Percentage | Detection Source |
    |----------|---------|------------|------------------|
    | Elixir | 1.15.7 | 90% | mix.exs |
    | JavaScript | ES2022 | 10% | package.json |

    ## Frameworks & Libraries

    ### Backend
    | Name | Version | Purpose |
    |------|---------|---------|
    | Phoenix | 1.7.10 | Web framework |
    | Ecto | 3.11.0 | Database wrapper |

    ## Database
    - **Type:** PostgreSQL
    - **Adapter:** Postgrex

    ## Infrastructure
    - **Deployment:** Fly.io
    """
  end

  @doc """
  Returns a mock architecture response.
  """
  def architecture_response do
    """
    # Architecture Analysis

    ## Application Structure
    - **Type:** Monolith
    - **Root namespace:** MyApp
    - **Web namespace:** MyAppWeb

    ## Context Map

    ### MyApp.Orders
    - **Purpose:** Order management
    - **Schemas:** Order, LineItem
    - **Public API:** create_order/1, list_orders/1

    ## Entry Points
    - `/orders` → OrderLive.Index
    """
  end

  @doc """
  Returns a mock conventions response.
  """
  def conventions_response do
    """
    # Codebase Conventions

    ## Naming Conventions

    ### Modules
    - Contexts: Plural (e.g., MyApp.Orders)
    - Schemas: Singular (e.g., MyApp.Orders.Order)

    ### Functions
    - Fetch single: get_* returns nil, fetch_* returns tuple
    - List multiple: list_*

    ## Code Patterns

    ### Error Handling
    - Context functions return {:ok, result} or {:error, changeset}
    """
  end

  @doc """
  Returns a mock feature location response.
  """
  def feature_location_response do
    """
    # Feature Location: Status Dropdown

    ## Search Terms Used
    - Primary: status, dropdown
    - Secondary: enum, select

    ## Schema Definitions

    ### Primary Schema
    - **File:** lib/my_app/orders/order.ex
    - **Line:** 15
    - **Code:** field :status, Ecto.Enum, values: [:pending, :confirmed]

    ## Summary
    | Category | Files Found | Primary File |
    |----------|-------------|--------------|
    | Schema | 1 | lib/my_app/orders/order.ex |
    """
  end

  @doc """
  Returns a mock impact analysis response.
  """
  def impact_analysis_response do
    """
    # Impact Analysis: Status Dropdown

    ## Direct Dependencies (Must Change)

    | File | Reason | Complexity |
    |------|--------|------------|
    | lib/my_app/orders/order.ex | Schema definition | Medium |

    ## No Impact (Verified)
    - lib/my_app/accounts/* - No status references

    ## Risk Assessment
    | Risk | Severity | Mitigation |
    |------|----------|------------|
    | API Breaking | High | Version API |
    """
  end

  @doc """
  Returns a mock change planning response.
  """
  def change_planning_response do
    """
    # Feature: Add Status Dropdown

    ## Executive Summary
    This feature adds a configurable status dropdown to orders.

    ## Tickets

    ### Ticket #1: Add Status Enum to Schema

    **Type:** Task
    **Priority:** High
    **Estimate:** Small
    **Depends On:** None
    **Blocks:** #2

    #### Description
    Add the status enum field to the Order schema.

    #### Files to Modify
    | File | Changes |
    |------|---------|
    | lib/my_app/orders/order.ex | Add status field |

    #### Acceptance Criteria
    - [ ] Status field added to schema
    - [ ] Migration created

    ### Ticket #2: Update Form Component

    **Type:** Task
    **Priority:** High
    **Estimate:** Small
    **Depends On:** #1
    **Blocks:** None

    #### Description
    Add status dropdown to the order form.

    #### Files to Modify
    | File | Changes |
    |------|---------|
    | lib/my_app_web/live/order_live/form.ex | Add dropdown |

    #### Acceptance Criteria
    - [ ] Dropdown displays status options
    - [ ] Selection updates form state

    ## Estimated Total Effort

    | Category | Tickets | Points |
    |----------|---------|--------|
    | Backend | 1 | 2 |
    | Frontend | 1 | 2 |
    | **Total** | **2** | **4** |
    """
  end
end
