// Removes ONLY the data created by seed-001-meeting-room-booking.apex
// (bookings of the 10 seed rooms, then the rooms themselves).
// Run:  sf apex run --file scripts/apex/cleanup-001-meeting-room-booking.apex --target-org estudos27

List<String> seedRoomNames = new List<String>{
  'Sala Ipê', 'Sala Jacarandá', 'Sala Araucária', 'Auditório Pau-Brasil', 'Sala Buriti',
  'Sala Cerrado', 'Sala Mata Atlântica', 'Sala Pantanal', 'Cabine Caatinga', 'Sala Pampa'
};
List<Room_Booking__c> bookings = [
  SELECT Id FROM Room_Booking__c WHERE Meeting_Room__r.Name IN :seedRoomNames
];
List<Meeting_Room__c> rooms = [SELECT Id FROM Meeting_Room__c WHERE Name IN :seedRoomNames];
delete bookings;
delete rooms;
System.debug(LoggingLevel.ERROR, 'CLEANUP_RESULT bookings=' + bookings.size() + ' rooms=' + rooms.size());
