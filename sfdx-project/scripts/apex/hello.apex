// Use .apex files to store anonymous Apex.
// You can execute anonymous Apex in VS Code by selecting the
//     apex text and running the command:
//     SFDX: Execute Anonymous Apex with Currently Selected Text
// You can also execute the entire file by running the command:
//     SFDX: Execute Anonymous Apex with Editor Contents

// List<Candidate__c> cList = CandidatesCallout.getCandidates('partial', 'large');
// for (Candidate__c c : cList) {
//     System.debug(c);
// }

GetCandidatesBatch job = new GetCandidatesBatch('complete', null);
Database.executeBatch(job);