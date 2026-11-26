/**
 * Spec 001 / REQ-020: limits come from Booking_Setting__mdt.Default.
 */
@IsTest
private class BookingSettingsTest {
  @IsTest
  static void readsDefaultRecord() {
    Booking_Setting__mdt expected = Booking_Setting__mdt.getInstance('Default');
    Test.startTest();
    Integer minMinutes = BookingSettings.minDurationMinutes();
    Integer maxMinutes = BookingSettings.maxDurationMinutes();
    Integer maxDays = BookingSettings.maxAdvanceDays();
    Test.stopTest();
    Assert.areEqual(
      expected.Min_Duration_Minutes__c.intValue(),
      minMinutes,
      'Min duration from Default record'
    );
    Assert.areEqual(
      expected.Max_Duration_Minutes__c.intValue(),
      maxMinutes,
      'Max duration from Default record'
    );
    Assert.areEqual(
      expected.Max_Advance_Days__c.intValue(),
      maxDays,
      'Max advance days from Default record'
    );
  }

  @IsTest
  static void missingRecordThrowsClearError() {
    BookingSettings.recordName = 'Does_Not_Exist';
    String message;
    Test.startTest();
    try {
      BookingSettings.minDurationMinutes();
    } catch (BookingSettings.BookingSettingsException e) {
      message = e.getMessage();
    }
    Test.stopTest();
    Assert.isNotNull(
      message,
      'A missing settings record must raise BookingSettingsException'
    );
    Assert.isTrue(
      message.contains('Does_Not_Exist'),
      'The error should name the missing record: ' + message
    );
  }
}
