/*
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* GetCandidatesBatch: Batchable class for inserting Candidates from a Heroku endpoint
*
*   Full description
*
* Constructor:
*     - <Insert constructor here>
*
* Methods:
*     - <Insert methods here>
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @author         Federico Abella   <federico.abella@cloudgaia.com>
* @modifiedBy     Federico Abella   <federico.abella@cloudgaia.com>
* @maintainedBy   Federico Abella   <federico.abella@cloudgaia.com>
* @version        1.0
* @created        2022-06-14
* @modified       2022-06-14
* @systemLayer    Asynchronous/Batch/Callouts
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @changes
* ─────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
public class GetCandidatesBatch implements Database.Batchable<sObject>, Database.Stateful, 
    Database.AllowsCallouts
{
    
    private final String mode;
    private final String size;
    private Integer receivedCandidates;
    private Integer insertedCandidates;
    private String insertionErrors;


    public GetCandidatesBatch(String mode, String size) {
        this.mode = mode;
        this.size = size;
        this.receivedCandidates = 0;
        this.insertedCandidates = 0;
        this.insertionErrors = '';
    }

    public List<Candidate__c> start(Database.BatchableContext ctx) {

        List<Candidate__c> candidateList = new List<Candidate__c>();
        try {
            candidateList = CandidatesCallout.getCandidates(this.mode, this.size);
        } catch (Exception e) {
            DeveloperLogHandler.createDevLog(
                DeveloperLogHandler.LOGTYPE.ERROR,
                'GetCandidatesBatch Exception: ' + System.now(),
                'Exception Message: ' + e.getMessage() + '\n' 
                + 'Trace String: ' + e.getStackTraceString()
            );
            System.abortJob(ctx.getJobId());
        }

        return candidateList;
    }

    public void execute (Database.BatchableContext ctx, List<Candidate__c> candidatesBatch) {
        /*
        * This would be the place for some post-processing on the objects returned from the callout.
        * For simplicity's sake, in this demo we're just going to insert those objects, but keep
        * track of received and inserted totals, as well as any errors found.
        */

        //  Update the total number of received candidates
        this.receivedCandidates += candidatesBatch.size(); 

        List<Database.SaveResult> saveResults = Database.insert(candidatesBatch, false);
        for (Database.SaveResult result : saveResults) {
            if (!result.isSuccess()) {
                this.insertionErrors += 'Errors during insert: ' 
                    + JSON.serialize(
                        candidatesBatch.get(
                            saveResults.indexOf(result)
                        )
                    )
                    + '\n';
                for (Database.Error error : result.getErrors()) {
                    this.insertionErrors += error.getStatusCode()
                        + ':' + error.getFields()
                        + ':' + error.getMessage();
                }
                this.insertionErrors += '\n\n';
            } else {
                this.insertedCandidates += 1;
            }
        }
    }

    public void finish (Database.BatchableContext ctx) {

        DeveloperLogHandler.LOGTYPE logType = DeveloperLogHandler.LOGTYPE.INFO;
        if (String.isNotBlank(this.insertionErrors)) {
            logType = DeveloperLogHandler.LOGTYPE.WARNING;
            this.insertionErrors = 'Errors Found:\n' + this.insertionErrors;
        }

        DeveloperLogHandler.createDevLog(
            logType,
            'GetCandidatesBatch Finished: ' + System.now(), 
            'Total Received Candidates: ' + this.receivedCandidates + '\n'
            + 'Total Inserted Candidates: ' + this.insertedCandidates + '\n'
            + this.insertionErrors
        );
        
    }
}
