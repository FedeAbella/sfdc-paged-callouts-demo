// Use .apex files to store anonymous Apex.
// You can execute anonymous Apex in VS Code by selecting the
//     apex text and running the command:
//     SFDX: Execute Anonymous Apex with Currently Selected Text
// You can also execute the entire file by running the command:
//     SFDX: Execute Anonymous Apex with Editor Contents

// GetCandidatesBatch batchJob = new GetCandidatesBatch(
//     CandidatesCallout.Modes.PARTIAL,
//     CandidatesCallout.Sizes.LARGE
// );
// Database.executeBatch(batchJob);

// CandidatesCallout.quickDemo = true;
// GetCandidatesPagedQueueable job = new GetCandidatesPagedQueueable(
//     new GetCandidatesPagedQueueable.PagingAggregator(), 
//     1,
//     5000,
//     1,
//     1,
//     true
// );
// System.enqueueJob(job);
// CandidatesCallout.quickDemo = true;
System.debug(CandidatesCallout.quickDemo);