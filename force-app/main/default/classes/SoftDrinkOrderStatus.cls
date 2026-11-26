public without sharing class SoftDrinkOrderStatus {
  @InvocableMethod(
    label='Order Status'
    description='Return Status of the Soft Drink Order , when user ask for it, for example user can say what is the status of My Soft Drink order ABC'
  )
  public static List<String> getStatus(List<Integer> orderNumber) {
    Soft_Drink_Order__c sd = [
      SELECT ID, Status__c
      FROM Soft_Drink_Order__c
      WHERE Order_Number__c = :orderNumber[0]
    ];
    return new List<String>{ sd.Status__c };
  }
}
