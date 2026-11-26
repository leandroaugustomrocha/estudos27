/**
 * Reads the room booking limits from Booking_Setting__mdt (REQ-020).
 * getInstance on Custom Metadata does not consume SOQL queries.
 */
public with sharing class BookingSettings {
  @TestVisible
  private static String recordName = 'Default';

  /** Lets tests change the limits without deploying metadata (AC-027). */
  @TestVisible
  private static Booking_Setting__mdt overrideSetting;

  public class BookingSettingsException extends Exception {
  }

  public static Integer minDurationMinutes() {
    return current().Min_Duration_Minutes__c.intValue();
  }

  public static Integer maxDurationMinutes() {
    return current().Max_Duration_Minutes__c.intValue();
  }

  public static Integer maxAdvanceDays() {
    return current().Max_Advance_Days__c.intValue();
  }

  private static Booking_Setting__mdt current() {
    if (overrideSetting != null) {
      return overrideSetting;
    }
    Booking_Setting__mdt setting = Booking_Setting__mdt.getInstance(recordName);
    if (setting == null) {
      throw new BookingSettingsException(
        'Booking_Setting__mdt record "' +
          recordName +
          '" was not found. Create it in Setup > Custom Metadata Types.'
      );
    }
    return setting;
  }
}
