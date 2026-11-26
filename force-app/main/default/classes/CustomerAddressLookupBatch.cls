/**
 * Background postal code lookup for customers saved outside the customer form: imports,
 * integrations and the standard "New" button (spec 002, REQ-008, REQ-024, REQ-025).
 *
 * Batch Apex (plan D-4): the platform splits the customers into blocks of BATCH_SIZE and
 * each block has its own 120 s callout budget, so 200 customers need no chained jobs
 * (Developer Edition allows only 5 chained Queueables). Customers whose lookup does not
 * fit in the budget are postponed and retried by a new batch in finish().
 */
public with sharing class CustomerAddressLookupBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
  /** Customers per block: keeps the callouts of one block within the 120 s transaction limit. */
  public static final Integer BATCH_SIZE = 20;
  /** Total attempts for postponed customers (first run included). */
  public static final Integer MAX_ATTEMPTS = 3;

  /** Below this, there is no point in starting another callout in this block. */
  private static final Integer MIN_CALLOUT_MS = 1000;

  /** Callout budget per block; tests lower it to simulate a slow service. */
  @TestVisible
  private static Integer budgetMs = ViaCepCallout.TIMEOUT_MS;

  private final Set<Id> customerIds;
  private final Integer attempt;
  @TestVisible
  private final Set<Id> postponedIds = new Set<Id>();

  public CustomerAddressLookupBatch(Set<Id> customerIds) {
    this(customerIds, 1);
  }

  @TestVisible
  private CustomerAddressLookupBatch(Set<Id> customerIds, Integer attempt) {
    this.customerIds = customerIds;
    this.attempt = attempt;
  }

  /** Starts the lookup for the given customers. */
  public static Id run(Set<Id> customerIds) {
    return Database.executeBatch(
      new CustomerAddressLookupBatch(customerIds),
      BATCH_SIZE
    );
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocatorWithBinds(
      'SELECT Id, Postal_Code__c, Street__c, District__c, City__c, State__c, Address_Note__c ' +
      'FROM Customer__c WHERE Id IN :customerIds AND Postal_Code__c != NULL',
      new Map<String, Object>{ 'customerIds' => customerIds },
      AccessLevel.USER_MODE
    );
  }

  public void execute(
    Database.BatchableContext context,
    List<Customer__c> customers
  ) {
    Map<String, ViaCepCallout.Result> resultsByPostalCode = lookUpDistinctPostalCodes(
      customers
    );

    List<Customer__c> changed = new List<Customer__c>();
    for (Customer__c customer : customers) {
      ViaCepCallout.Result result = resultsByPostalCode.get(
        customer.Postal_Code__c
      );
      if (result == null) {
        postponedIds.add(customer.Id); // did not fit in this block's callout budget
      } else if (applyResult(customer, result)) {
        changed.add(customer);
      }
    }
    if (changed.isEmpty()) {
      return;
    }
    List<Database.SaveResult> results = Database.update(
      changed,
      false,
      AccessLevel.USER_MODE
    );
    for (Integer i = 0; i < results.size(); i++) {
      if (!results[i].isSuccess()) {
        System.debug(
          LoggingLevel.ERROR,
          'Address lookup could not update customer ' +
            changed[i].Id +
            ': ' +
            results[i].getErrors()
        );
      }
    }
  }

  public void finish(Database.BatchableContext context) {
    if (postponedIds.isEmpty()) {
      return;
    }
    if (attempt >= MAX_ATTEMPTS) {
      System.debug(
        LoggingLevel.WARN,
        'Address lookup gave up after ' +
          attempt +
          ' attempts for customers: ' +
          postponedIds
      );
      return;
    }
    if (!Test.isRunningTest()) {
      Database.executeBatch(
        new CustomerAddressLookupBatch(postponedIds, attempt + 1),
        BATCH_SIZE
      );
    }
  }

  /**
   * One callout per distinct postal code, within the block budget. A lookup cut short by
   * the remaining budget (timeout below 120 s) that comes back UNAVAILABLE is postponed,
   * not treated as "service down" (REQ-025 only covers the service being down).
   */
  private Map<String, ViaCepCallout.Result> lookUpDistinctPostalCodes(
    List<Customer__c> customers
  ) {
    Map<String, ViaCepCallout.Result> resultsByPostalCode = new Map<String, ViaCepCallout.Result>();
    Long startedAt = System.currentTimeMillis();
    for (Customer__c customer : customers) {
      if (resultsByPostalCode.containsKey(customer.Postal_Code__c)) {
        continue;
      }
      Long remaining = budgetMs - (System.currentTimeMillis() - startedAt);
      if (remaining < MIN_CALLOUT_MS) {
        break;
      }
      Integer timeoutMs = Math.min(
        ViaCepCallout.TIMEOUT_MS,
        remaining.intValue()
      );
      ViaCepCallout.Result result = ViaCepCallout.lookup(
        customer.Postal_Code__c.replace('-', ''),
        timeoutMs
      );
      Boolean cutShort =
        result.status == ViaCepCallout.Status.UNAVAILABLE &&
        timeoutMs < ViaCepCallout.TIMEOUT_MS;
      if (!cutShort) {
        resultsByPostalCode.put(customer.Postal_Code__c, result);
      }
    }
    return resultsByPostalCode;
  }

  /** Returns true when the customer changed. */
  private Boolean applyResult(
    Customer__c customer,
    ViaCepCallout.Result result
  ) {
    if (result.status == ViaCepCallout.Status.FOUND) {
      Boolean changed = false;
      if (String.isBlank(customer.Street__c) && result.street != null) {
        customer.Street__c = result.street;
        changed = true;
      }
      if (String.isBlank(customer.District__c) && result.district != null) {
        customer.District__c = result.district;
        changed = true;
      }
      if (String.isBlank(customer.City__c) && result.city != null) {
        customer.City__c = result.city;
        changed = true;
      }
      if (String.isBlank(customer.State__c) && result.state != null) {
        customer.State__c = result.state;
        changed = true;
      }
      return changed;
    }
    if (result.status == ViaCepCallout.Status.NOT_FOUND) {
      customer.Address_Note__c = String.format(
        System.Label.Customer_Postal_Code_Removed_Note,
        new List<Object>{ customer.Postal_Code__c, Date.today().format() }
      );
      customer.Postal_Code__c = null;
      return true;
    }
    return false; // UNAVAILABLE: keep the customer as imported (REQ-025)
  }
}
