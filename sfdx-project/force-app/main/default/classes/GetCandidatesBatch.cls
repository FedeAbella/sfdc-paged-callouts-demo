/*
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* GetCandidatesBatch: Batchable class for upserting Candidates from Heroku endpoint via External ID
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
    private Integer upsertedCandidates;
    private Integer insertedCandidates;
    private Integer updatedCandidates;
    private String upsertErrors;


    public GetCandidatesBatch(String mode, String size) {
        this.mode = mode;
        this.size = size;
        this.receivedCandidates = 0;
        this.upsertedCandidates = 0;
        this.insertedCandidates = 0;
        this.updatedCandidates = 0;
        this.upsertErrors = '';
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
        * For simplicity's sake, in this demo we're just going to upsert those objects, but keep
        * track of received and upserted (created or updated) totals, as well as any errors found.
        */

        //  Update the total number of received candidates
        this.receivedCandidates += candidatesBatch.size(); 

        List<Database.UpsertResult> saveResults = Database.upsert(
            candidatesBatch, Candidate__c.Fields.External_ID__c, false
        );
        for (Database.UpsertResult result : saveResults) {
            if (!result.isSuccess()) {
                this.upsertErrors += 'Errors during upsert: ' 
                    + JSON.serialize(
                        candidatesBatch.get(
                            saveResults.indexOf(result)
                        )
                    )
                    + '\n';
                for (Database.Error error : result.getErrors()) {
                    this.upsertErrors += error.getStatusCode()
                        + ':' + error.getFields()
                        + ':' + error.getMessage();
                }
                this.upsertErrors += '\n\n';
            } else {
                this.upsertedCandidates += 1;
                if (result.isCreated()) {
                    this.insertedCandidates += 1;
                } else {
                    this.updatedCandidates += 1;
                }
            }
        }
    }

    public void finish (Database.BatchableContext ctx) {

        DeveloperLogHandler.LOGTYPE logType = DeveloperLogHandler.LOGTYPE.INFO;
        if (String.isNotBlank(this.upsertErrors)) {
            logType = DeveloperLogHandler.LOGTYPE.WARNING;
            this.upsertErrors = 'Errors Found:\n' + this.upsertErrors;
        }

        DeveloperLogHandler.createDevLog(
            logType,
            'GetCandidatesBatch Finished: ' + System.now(), 
            'Received Candidates: ' + this.receivedCandidates + '\n'
            + 'Upserted Candidates: ' + this.upsertedCandidates + '\n'
            + 'Inserted Candidates: ' + this.insertedCandidates + '\n'
            + 'Updated Candidates: ' + this.updatedCandidates + '\n'
            + this.upsertErrors
        );
        
    }
}
