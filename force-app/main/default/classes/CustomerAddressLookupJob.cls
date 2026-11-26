/**
 * Background postal code lookup for customers saved outside the customer form: imports,
 * integrations and the standard "New" button (spec 002, REQ-008, REQ-024, REQ-025).
 *
 * One execution handles BATCH_SIZE customers and chains the rest. A transaction may spend
 * at most 120 s on callouts in total, so each lookup waits at most what is left of that
 * budget, and customers whose postal code does not fit go back to the queue.
 */
public with sharing class CustomerAddressLookupJob implements Queueable, Database.AllowsCallouts {
  /** Customers per execution: keeps the callouts of one run within the 120 s transaction limit. */
  public static final Integer BATCH_SIZE = 20;

  /** Below this, there is no point in starting another callout in this transaction. */
  private static final Integer MIN_CALLOUT_MS = 1000;

  private final List<Id> customerIds;

  public CustomerAddressLookupJob(List<Id> customerIds) {
    this.customerIds = customerIds;
  }

  public void execute(QueueableContext context) {
    List<Id> currentIds = new List<Id>();
    List<Id> nextIds = new List<Id>();
    for (Id customerId : customerIds) {
      if (currentIds.size() < BATCH_SIZE) {
        currentIds.add(customerId);
      } else {
        nextIds.add(customerId);
      }
    }

    List<Customer__c> customers = [
      SELECT
        Id,
        Postal_Code__c,
        Street__c,
        District__c,
        City__c,
        State__c,
        Address_Note__c
      FROM Customer__c
      WHERE Id IN :currentIds AND Postal_Code__c != NULL
      WITH USER_MODE
    ];

    Map<String, ViaCepCallout.Result> resultsByPostalCode = lookUpDistinctPostalCodes(
      customers
    );

    List<Customer__c> changed = new List<Customer__c>();
    for (Customer__c customer : customers) {
      ViaCepCallout.Result result = resultsByPostalCode.get(
        customer.Postal_Code__c
      );
      if (result == null) {
        nextIds.add(customer.Id); // did not fit in this transaction's callout budget
      } else if (applyResult(customer, result)) {
        changed.add(customer);
      }
    }
    if (!changed.isEmpty()) {
      Database.update(changed, false, AccessLevel.USER_MODE);
    }
    // Chained Queueable jobs cannot run inside Apex tests; the test covers one execution.
    if (!nextIds.isEmpty() && !Test.isRunningTest()) {
      System.enqueueJob(new CustomerAddressLookupJob(nextIds));
    }
  }

  private Map<String, ViaCepCallout.Result> lookUpDistinctPostalCodes(
    List<Customer__c> customers
  ) {
    Map<String, ViaCepCallout.Result> resultsByPostalCode = new Map<String, ViaCepCallout.Result>();
    Long startedAt = System.currentTimeMillis();
    for (Customer__c customer : customers) {
      if (resultsByPostalCode.containsKey(customer.Postal_Code__c)) {
        continue;
      }
      Long remaining =
        ViaCepCallout.TIMEOUT_MS - (System.currentTimeMillis() - startedAt);
      if (remaining < MIN_CALLOUT_MS) {
        break;
      }
      resultsByPostalCode.put(
        customer.Postal_Code__c,
        ViaCepCallout.lookup(
          customer.Postal_Code__c.replace('-', ''),
          Math.min(ViaCepCallout.TIMEOUT_MS, remaining.intValue())
        )
      );
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
