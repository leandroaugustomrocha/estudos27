// Seed data for spec 001 (meeting room booking): 10 rooms + 200 bookings.
// Run:   sf apex run --file scripts/apex/seed-001-meeting-room-booking.apex --target-org estudos27
// Undo:  scripts/apex/cleanup-001-meeting-room-booking.apex
//
// Every booking goes through RoomBookingTrigger (no bypass), so the data is valid by
// construction: weekdays, inside each room's hours (running user's time zone), 30 min to
// 2 h, from tomorrow on, no overlaps. The running user is the organizer of every booking
// and needs the Meeting_Room_Admin permission set.

List<String> seedRoomNames = new List<String>{
  'Sala Ipê', 'Sala Jacarandá', 'Sala Araucária', 'Auditório Pau-Brasil', 'Sala Buriti',
  'Sala Cerrado', 'Sala Mata Atlântica', 'Sala Pantanal', 'Cabine Caatinga', 'Sala Pampa'
};
Assert.areEqual(
  0,
  [SELECT COUNT() FROM Meeting_Room__c WHERE Name IN :seedRoomNames],
  'Seed already loaded: run cleanup-001-meeting-room-booking.apex first.'
);

Integer randomBetween(Integer low, Integer high) {
  return low + Math.mod(Math.abs(Crypto.getRandomInteger()), high - low + 1);
}

Meeting_Room__c room(String name, Integer capacity, Integer openHour, Integer closeHour, Boolean active) {
  return new Meeting_Room__c(
    Name = name,
    Capacity__c = capacity,
    Opening_Time__c = Time.newInstance(openHour, 0, 0, 0),
    Closing_Time__c = Time.newInstance(closeHour, 0, 0, 0),
    Is_Active__c = active
  );
}

// ---------- rooms ----------
List<Meeting_Room__c> rooms = new List<Meeting_Room__c>{
  room('Sala Ipê', 6, 8, 18, true),
  room('Sala Jacarandá', 10, 8, 18, true),
  room('Sala Araucária', 4, 9, 17, true),
  room('Auditório Pau-Brasil', 60, 7, 19, true),
  room('Sala Buriti', 8, 8, 18, true),
  room('Sala Cerrado', 12, 8, 20, true),
  room('Sala Mata Atlântica', 20, 8, 18, true),
  room('Sala Pantanal', 6, 9, 18, true),
  room('Cabine Caatinga', 2, 8, 18, true),
  room('Sala Pampa', 8, 8, 18, false) // inactive: no bookings, used to test REQ-008
};
insert rooms;

// ---------- bookings ----------
List<String> subjects = new List<String>{
  'Daily do time de Vendas', 'Planejamento da sprint', 'Revisão do pipeline do trimestre',
  'Entrevista - Dev Salesforce Pleno', '1:1 com a liderança', 'Workshop de Agentforce',
  'Alinhamento com o cliente Acme', 'Retrospectiva da sprint', 'Onboarding de novos colaboradores',
  'Kick-off do projeto CRM', 'Comitê de mudanças (CAB)', 'Demo para stakeholders',
  'Treinamento de Flows', 'Orçamento 2027', 'Brainstorm de marketing', 'Revisão de contrato',
  'Café com o time de Suporte', 'Apresentação de resultados', 'Refinamento do backlog',
  'Treinamento de LWC', 'Revisão de arquitetura', 'Reunião com parceiro de integração'
};
List<Integer> durations = new List<Integer>{ 30, 45, 60, 60, 60, 90, 120 };
Date knownMonday = Date.newInstance(1900, 1, 1);

List<Room_Booking__c> bookings = new List<Room_Booking__c>();
Date day = Date.today().addDays(1);
Integer daysScanned = 0;
while (bookings.size() < 200 && daysScanned < 80) {
  Integer isoDay = Math.mod(knownMonday.daysBetween(day), 7) + 1;
  if (isoDay <= 5) {
    for (Meeting_Room__c r : rooms) {
      if (!r.Is_Active__c) {
        continue;
      }
      Integer closeMinute = r.Closing_Time__c.hour() * 60;
      Integer cursor = r.Opening_Time__c.hour() * 60 + 30 * randomBetween(0, 2);
      while (bookings.size() < 200) {
        Integer duration = durations[randomBetween(0, durations.size() - 1)];
        if (cursor + duration > closeMinute) {
          break;
        }
        if (randomBetween(1, 100) <= 35) {
          Datetime startAt = Datetime.newInstance(day, Time.newInstance(0, 0, 0, 0)).addMinutes(cursor);
          Integer capacity = r.Capacity__c.intValue();
          bookings.add(
            new Room_Booking__c(
              Name = subjects[randomBetween(0, subjects.size() - 1)],
              Meeting_Room__c = r.Id,
              Start_Date_Time__c = startAt,
              End_Date_Time__c = startAt.addMinutes(duration),
              Attendee_Count__c = randomBetween(1, Math.min(capacity, 12)),
              Status__c = randomBetween(1, 100) <= 12 ? 'Cancelled' : 'Active'
            )
          );
        }
        cursor += duration + 30 * randomBetween(0, 2);
      }
    }
  }
  day = day.addDays(1);
  daysScanned++;
}

List<Database.SaveResult> results = Database.insert(bookings, false);
Integer saved = 0;
for (Integer i = 0; i < results.size(); i++) {
  if (results[i].isSuccess()) {
    saved++;
  } else {
    System.debug(LoggingLevel.ERROR, 'SEED_FAIL ' + bookings[i].Name + ': ' + results[i].getErrors()[0].getMessage());
  }
}
System.debug(LoggingLevel.ERROR, 'SEED_RESULT rooms=' + rooms.size() + ' bookings_built=' + bookings.size() + ' bookings_saved=' + saved + ' last_day=' + day.addDays(-1));
